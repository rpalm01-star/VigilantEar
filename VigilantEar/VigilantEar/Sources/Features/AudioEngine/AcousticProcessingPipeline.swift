@preconcurrency import AVFoundation
import Accelerate
import SoundAnalysis
import SwiftUI
import CoreLocation
import ShazamKit

actor AcousticProcessingPipeline {
    
    private let bufferSize: AVAudioFrameCount = 4096
    
    nonisolated let eventStream: AsyncStream<SoundEvent>
    private let continuation: AsyncStream<SoundEvent>.Continuation
    
    // THE NEW PIPE: Just for Shazam strings
    nonisolated let songStream: AsyncStream<String>
    private let songContinuation: AsyncStream<String>.Continuation
    
    private let fftProcessor: FFTProcessor
    
    // --- THE MULTI-TARGET TRACKER MEMORY ---
    struct ActiveThreat {
        var sessionID: UUID
        var dopplerTracker: SirenDopplerTracker
        var lastFrequency: Double
        var lastSeen: Date
    }
    
    private var activeThreats: [ActiveThreat] = []
    
    // MARK: - Doppler State Tracking
    private var dopplerFrequencyBuffer: [Double] = []
    private let maxDopplerBufferSize = 40
    private var dopplerBaselineCenter: Double?
    
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var resultsObserver: ThreatResultsObserver?
    
    // --- SHAZAM STATE ---
    private var shazamSession: SHSession?
    private var shazamDelegate: ShazamResultsObserver?
    private var lastShazamMatchTime: Date = Date.distantPast
    private var signatureGenerator = SHSignatureGenerator()
    private var accumulatedFrames: AVAudioFrameCount = 0
    private var sampleRate: Double = 44100.0
    private var framesPerSecond: Double = 44100.0
    
    private var latestBuffer: AVAudioPCMBuffer?
    private var latestTime: AVAudioTime?
    
    private var lastKnownLocation: CLLocationCoordinate2D? = nil
    
    // --- THE FIX: CPU THROTTLE STATE ---
    private var lastProcessTime: Date = Date.distantPast
    
    // --- THE FIX: COOLDOWN MEMORY ---
    // Tracks when we last saw a specific threat to prevent CoreML spam
    private var lastSeenThreats: [String: Date] = [:]
    
    private var logStep: String = ""
    private var logMessage: String = ""
    
    init() {
        let (stream, cont) = AsyncStream.makeStream(of: SoundEvent.self)
        self.eventStream = stream
        self.continuation = cont
        
        // Init the new pipe
        let (sStream, sCont) = AsyncStream.makeStream(of: String.self)
        self.songStream = sStream
        self.songContinuation = sCont
        
        self.fftProcessor = FFTProcessor(fftSize: Int(self.bufferSize))
    }
    
    // Called by the MicrophoneManager whenever the GPS updates
    public func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        self.lastKnownLocation = coordinate
    }
    
    func processAudio(buffer: AVAudioPCMBuffer, time: AVAudioTime) async {
        self.latestBuffer = buffer
        self.latestTime = time
        
        // 1. CoreML (Still the hero)
        streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        
        // 2. Shazam Matching Logic
        guard Date().timeIntervalSince(lastShazamMatchTime) > 15.0 else { return }
        
        // --- THE FIX: Create a proper Shazam-compatible format ---
        // ShazamKit loves 44100 or 48000 Mono.
        let shazamFormat = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1)!
        
        // Convert your stereo buffer to mono
        let converter = AVAudioConverter(from: buffer.format, to: shazamFormat)
        let monoBuffer = AVAudioPCMBuffer(pcmFormat: shazamFormat, frameCapacity: buffer.frameLength)!
        
        var error: NSError?
        converter?.convert(to: monoBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        // Append the converted mono buffer
        try? signatureGenerator.append(monoBuffer, at: time)
        accumulatedFrames += monoBuffer.frameLength
        
        // Match every ~10 seconds
        if accumulatedFrames >= AVAudioFrameCount(shazamFormat.sampleRate * 10) {
            let signature = signatureGenerator.signature()
            
            // LOG THIS: If this is 0.0, the append failed!
            print("🎵 Final Signature Duration: \(signature.duration)s")
            
            if signature.duration > 3.0 {
                shazamSession?.match(signature)
            }
            
            // RESET
            self.signatureGenerator = SHSignatureGenerator()
            self.accumulatedFrames = 0
        }
    }
    
    func registerSongMatch(title: String, artist: String) async {
        let now = Date()
        
        // THE COOLDOWN: Only announce a new song once every 60 seconds
        guard now.timeIntervalSince(lastShazamMatchTime) > 60.0 else { return }
        self.lastShazamMatchTime = now
        
        let customLabel = "🎵 \(title) by \(artist)"
        
        await PerformanceLogger.shared.logTelemetry(step: "SHAZAM", message: "Identified: \(customLabel)")
        
        // THE FIX: Yield the string directly to the UI, ignoring the map entirely!
        songContinuation.yield(customLabel)
    }
    
    func confirmThreatAndTrack(label: String, confidence: Double) async {
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) > 0.2 else { return }
        lastProcessTime = now
        
        // --- THE SWIFT 6 CONCURRENCY FIX ---
        // Safely hop to the MainActor ONCE to extract thread-safe values.
        // This prevents cross-actor violations later in the detached task!
        let (isVehicle, profileCeiling, profileMaxRange) = await MainActor.run {
            let p = SoundProfile.classify(label)
            return (p.isVehicle, p.ceiling, p.maxRange)
        }
        
        // 1. ML TRIGGER LOG
        let triggerMsg = "Heard: \(label) (Conf: \(String(format: "%.2f", confidence)))"
        await PerformanceLogger.shared.logTelemetry(step: "1_ML_TRIGGER", message: triggerMsg)
        
        guard let buffer = latestBuffer, let channelData = buffer.floatChannelData else { return }
        let peak = Array(UnsafeBufferPointer(start: channelData[0], count: min(Int(buffer.frameLength), 4096))).map(abs).max() ?? 0.0
        
        // 2. VOLUME GATE
        let minimumPeak: Float = isVehicle ? 0.02 : 0.04
        guard peak > minimumPeak else {
            await PerformanceLogger.shared.logTelemetry(step: "2_VOLUME_DROP", message: "Peak \(String(format: "%.3f", peak)) < \(minimumPeak)")
            return
        }
        
        var targets = self.fftProcessor.analyzeMultiple(samples: Array(UnsafeBufferPointer(start: channelData[0], count: 4096)), sampleRate: self.sampleRate, maxPeaks: 3)
        
        // 3. FFT HANDLING
        if targets.isEmpty && isVehicle {
            targets.append((frequency: 100.0, confidence: Float(confidence)))
        } else if targets.isEmpty {
            return
        }
        
        activeThreats.removeAll { now.timeIntervalSince($0.lastSeen) > 4.0 }
        
        for target in targets {
            let currentFreq = target.frequency
            var matchIndex: Int? = nil
            
            // THREAT MATCHING
            for (index, threat) in activeThreats.enumerated() {
                let threshold = isVehicle ? 500.0 : 40.0
                if abs(threat.lastFrequency - currentFreq) < threshold {
                    matchIndex = index
                    break
                }
            }
            
            // When updating the tracker, only use the frequency doppler if it's NOT a vehicle.
            let threatSessionID: UUID
            let dopplerResult: (isApproaching: Bool, shiftHz: Double)?
            
            if let index = matchIndex {
                activeThreats[index].lastFrequency = currentFreq
                activeThreats[index].lastSeen = now
                
                // THE FIX: Ignore frequency doppler for broadband vehicles
                if isVehicle {
                    dopplerResult = nil
                } else {
                    dopplerResult = activeThreats[index].dopplerTracker.update(with: currentFreq, confidence: target.confidence)
                }
                threatSessionID = activeThreats[index].sessionID
            } else {
                let newID = UUID()
                var newTracker = SirenDopplerTracker()
                dopplerResult = newTracker.update(with: currentFreq, confidence: target.confidence)
                activeThreats.append(ActiveThreat(sessionID: newID, dopplerTracker: newTracker, lastFrequency: currentFreq, lastSeen: now))
                threatSessionID = newID
            }
            
            // 4. DISTANCE & BEARING MATH
            Task.detached(priority: .userInitiated) { [weak self, threatSessionID] in
                guard let self = self else { return }
                
                let ambientFloor: Double = isVehicle ? 0.02 : 0.04
                
                // THE FIX: Use the extracted thread-safe constants instead of 'profile'
                let safePeak = min(max(Double(peak), ambientFloor), profileCeiling)
                let linearRatio = (profileCeiling - safePeak) / (profileCeiling - ambientFloor)
                
                // THE DISTANCE FIX
                // Decrease the vehicle curve from 3.5 to 2.2 to stop the "ganging up"
                let adjustedMaxRange = isVehicle ? 400.0 : profileMaxRange
                let curvePower = isVehicle ? 2.2 : 2.0 // <-- Relaxed this value
                let estimatedFeet = max(10.0, pow(linearRatio, curvePower) * adjustedMaxRange)
                let normalizedUI_Distance = estimatedFeet / 1000.0
                
                // BEARING FIX
                let exactMicDistance = await HardwareCalibration.micBaseline
                let rawAngle = self.fftProcessor.calculateTDOA(left: Array(UnsafeBufferPointer(start: channelData[0], count: 4096)),
                                                               right: Array(UnsafeBufferPointer(start: channelData[1], count: 4096)),
                                                               sampleRate: Double(44100),
                                                               micDistance: exactMicDistance) ?? 0.0
                
                // EVENT YIELD
                let newEvent = SoundEvent(
                    sessionID: threatSessionID,
                    timestamp: Date(),
                    threatLabel: label,
                    confidence: confidence,
                    bearing: rawAngle,
                    distance: normalizedUI_Distance,
                    energy: Float(safePeak),
                    dopplerRate: dopplerResult?.shiftHz != nil ? Float(dopplerResult!.shiftHz) : nil,
                    isApproaching: dopplerResult?.isApproaching ?? false,
                    latitude: await self.lastKnownLocation?.latitude,
                    longitude: await self.lastKnownLocation?.longitude
                )
                
                // THE FIX: Explicitly ignore the yield result with "_ ="
                await MainActor.run { _ = self.continuation.yield(newEvent) }
            }
        }
    }
    
    
    func setupAnalyzer(format: AVAudioFormat) throws {
        // Update the actor's math to match the actual hardware speed
        self.sampleRate = format.sampleRate
        self.framesPerSecond = format.sampleRate
        
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 1000)
        request.overlapFactor = 0.9
        
        let observer = ThreatResultsObserver(pipeline: self)
        self.resultsObserver = observer
        try streamAnalyzer?.add(request, withObserver: observer)
        
        self.signatureGenerator = SHSignatureGenerator()
        
        // --- SHAZAM SETUP ---
        let shazamObs = ShazamResultsObserver(pipeline: self)
        self.shazamDelegate = shazamObs
        self.shazamSession = SHSession()
        self.shazamSession?.delegate = shazamObs
    }
    
    private func updateDoppler(frequency: Double, confidence: Float) -> (isApproaching: Bool, shiftHz: Double)? {
        guard confidence > 0.3 else { return nil }
        
        dopplerFrequencyBuffer.append(frequency)
        if dopplerFrequencyBuffer.count > maxDopplerBufferSize {
            dopplerFrequencyBuffer.removeFirst()
        }
        
        guard dopplerFrequencyBuffer.count > 10 else { return nil }
        guard let minFreq = dopplerFrequencyBuffer.min(), let maxFreq = dopplerFrequencyBuffer.max() else { return nil }
        
        let currentCenter = (maxFreq + minFreq) / 2.0
        
        if dopplerBaselineCenter == nil {
            dopplerBaselineCenter = currentCenter
            return nil
        }
        
        dopplerBaselineCenter = (dopplerBaselineCenter! * 0.95) + (currentCenter * 0.05)
        let shift = currentCenter - dopplerBaselineCenter!
        let isApproaching = shift > 5.0
        
        return (isApproaching, shift)
    }
    
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float? {
        guard let channelData = buffer.floatChannelData else { return nil }
        var rms: Float = 0.0
        vDSP_rmsqv(channelData[0], 1, &rms, UInt(buffer.frameLength))
        return rms
    }
}

// MARK: - Core ML Results Observer
final class ThreatResultsObserver: NSObject, @unchecked Sendable, SNResultsObserving {
    private weak var pipeline: AcousticProcessingPipeline?
    
    nonisolated init(pipeline: AcousticProcessingPipeline) {
        self.pipeline = pipeline
        super.init()
    }
    
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        
        // Gather top 5 candidates (label, confidence)
        let topCandidates = classificationResult.classifications.prefix(5).map { ($0.identifier.lowercased(), $0.confidence) }
        
        Task { @MainActor in
            var finalLabel: String?
            var finalConfidence: Double = 0.0
            
            var pendingVehicleLabel: String?
            var pendingVehicleConf: Double = 0.0
            
            // Mutually Exclusive Priority Scanning
            for (label, conf) in topCandidates {
                let profile = SoundProfile.classify(label)
                
                // PRIORITY 1: Emergencies.
                if profile.isEmergency && conf > 0.25 {
                    finalLabel = label
                    finalConfidence = conf
                    break // Emergency found. Stop scanning entirely.
                }
                
                // PRIORITY 2: Vehicles.
                else if profile.isVehicle && conf > 0.20 && pendingVehicleLabel == nil {
                    pendingVehicleLabel = label
                    pendingVehicleConf = conf
                    // Do NOT break here. Keep scanning in case an emergency is lower in the list.
                }
            }
            
            // Resolution Phase: Assign the final threat based on priority rank
            if finalLabel == nil {
                if let vLabel = pendingVehicleLabel {
                    finalLabel = vLabel
                    finalConfidence = pendingVehicleConf
                }
                // PRIORITY 3: The standard fallback.
                else if let top = topCandidates.first, top.1 > 0.50 {
                    finalLabel = top.0
                    finalConfidence = top.1
                }
            }
            
            // Send it to the pipeline
            if let detectedLabel = finalLabel {
                Task {
                    await self.pipeline?.confirmThreatAndTrack(label: detectedLabel, confidence: finalConfidence)
                }
            }
        }
    }
}

// MARK: - Shazam Results Observer
final class ShazamResultsObserver: NSObject, @unchecked Sendable, SHSessionDelegate {
    private weak var pipeline: AcousticProcessingPipeline?
    
    nonisolated init(pipeline: AcousticProcessingPipeline) {
        self.pipeline = pipeline
        super.init()
    }
    
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        guard let mediaItem = match.mediaItems.first,
              let title = mediaItem.title,
              let artist = mediaItem.artist else { return }
        
        print("🎵 Shazam Match Found: \(title)")
        
        Task {
            await pipeline?.registerSongMatch(title: title, artist: artist)
        }
    }
    
    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        if let err = error {
            // This will tell us if it's a network issue or a signature issue
            print("🎵 Shazam Error: \(err.localizedDescription)")
        } else {
            // This prints every few seconds while it's trying to listen
            print("🎵 Shazam: Listening for The Doors... no match yet.")
        }
    }
}
