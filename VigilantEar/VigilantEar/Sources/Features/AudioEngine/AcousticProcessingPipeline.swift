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
    
    // --- THE NEW PIPE: Shazam strings (now Optional to handle fades) ---
    nonisolated let songStream: AsyncStream<String?>
    private let songContinuation: AsyncStream<String?>.Continuation
    
    private let fftProcessor: FFTProcessor
    
    // --- THE MULTI-TARGET TRACKER MEMORY ---
    struct ActiveThreat {
        var sessionID: UUID
        var dopplerTracker: SirenDopplerTracker
        var lastFrequency: Double
        var lastBearing: Double // <-- NEW: Remember the spatial angle
        var lastSeen: Date
        var category: ThreatCategory
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
    private var signatureGenerator = SHSignatureGenerator()
    private var accumulatedFrames: AVAudioFrameCount = 0
    private var sampleRate: Double = 44100.0
    
    // --- THE NEW SHAZAM STATE MACHINE ---
    private var isMusicCurrentlyPlaying = false
    private var lastMusicDetectedTime: Date = .distantPast
    private var lastShazamMatchTime: Date = .distantPast
    private var hasMatchedCurrentSong = false
    private var currentSongLabel: String? = nil
    
    private var latestBuffer: AVAudioPCMBuffer?
    private var latestTime: AVAudioTime?
    
    private var lastKnownLocation: CLLocationCoordinate2D? = nil
    
    // --- CPU THROTTLE STATE ---
    private var lastProcessTime: Date = .distantPast
    
    // Tracks when we last saw a specific threat to prevent CoreML spam
    private var lastSeenThreats: [String: Date] = [:]
    
    private var logStep: String = ""
    private var logMessage: String = ""
    
    init() {
        let (stream, cont) = AsyncStream.makeStream(of: SoundEvent.self)
        self.eventStream = stream
        self.continuation = cont
        
        // Init the new pipe (Now accepts String? so we can yield nil)
        let (sStream, sCont) = AsyncStream.makeStream(of: String?.self)
        self.songStream = sStream
        self.songContinuation = sCont
        
        self.fftProcessor = FFTProcessor(fftSize: Int(self.bufferSize))
    }
    
    public func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        self.lastKnownLocation = coordinate
    }
    
    func processAudio(buffer: AVAudioPCMBuffer, time: AVAudioTime) async {
        self.latestBuffer = buffer
        self.latestTime = time
        
        // 1. CoreML (Still the hero)
        streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        
        // --- 2. MUSIC FADE CHECK ---
        // If 5 seconds pass without hearing music, clear the UI and go to sleep
        if isMusicCurrentlyPlaying && Date().timeIntervalSince(lastMusicDetectedTime) > 5.0 {
            isMusicCurrentlyPlaying = false
            hasMatchedCurrentSong = false
            currentSongLabel = nil
            print("🎵 Music vanished from radar. Clearing UI.")
            _ = songContinuation.yield(nil)
            return
        }
        
        // --- 3. THE "SMART TTL" SONG CHECKER ---
        if isMusicCurrentlyPlaying && hasMatchedCurrentSong {
            // It's been 3 minutes. The track probably changed. Wake up Shazam!
            if Date().timeIntervalSince(lastShazamMatchTime) > 180.0 {
                hasMatchedCurrentSong = false
                self.signatureGenerator = SHSignatureGenerator()
                self.accumulatedFrames = 0
                print("🎵 3-minute TTL hit. Waking Shazam to check for a track change...")
            } else {
                return // Still locked, save CPU
            }
        }
        
        // --- 4. SMART SHAZAM MATCHING ---
        // ONLY collect audio if we are actively searching
        guard isMusicCurrentlyPlaying && !hasMatchedCurrentSong else { return }
        
        let shazamFormat = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1)!
        let converter = AVAudioConverter(from: buffer.format, to: shazamFormat)
        let monoBuffer = AVAudioPCMBuffer(pcmFormat: shazamFormat, frameCapacity: buffer.frameLength)!
        
        var error: NSError?
        converter?.convert(to: monoBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        try? signatureGenerator.append(monoBuffer, at: time)
        accumulatedFrames += monoBuffer.frameLength
        
        // Try matching every ~8 seconds while searching
        if accumulatedFrames >= AVAudioFrameCount(shazamFormat.sampleRate * 8) {
            let signature = signatureGenerator.signature()
            if signature.duration > 3.0 {
                shazamSession?.match(signature)
            }
            self.signatureGenerator = SHSignatureGenerator()
            self.accumulatedFrames = 0
        }
    }
    
    func registerSongMatch(title: String, artist: String) async {
        let customLabel = "🎵 \(title) by \(artist)"
        
        // If it's the exact same song, just silently reset the 3-minute timer and go back to sleep
        if customLabel == currentSongLabel {
            hasMatchedCurrentSong = true
            lastShazamMatchTime = Date()
            return
        }
        
        // NEW SONG FOUND!
        currentSongLabel = customLabel
        hasMatchedCurrentSong = true
        lastShazamMatchTime = Date()
        
        await PerformanceLogger.shared.logTelemetry(step: "SHAZAM", message: "Identified: \(customLabel)")
        _ = songContinuation.yield(customLabel)
    }
    
    func confirmThreatAndTrack(label: String, confidence: Double) async {
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) > 0.2 else { return }
        lastProcessTime = now
        
        // FETCH EVERYTHING AT ONCE ON THE MAIN ACTOR
        let (isVehicle, profileCeiling, profileMaxRange, currentCategory) = await MainActor.run {
            let p = SoundProfile.classify(label)
            return (p.isVehicle, p.ceiling, p.maxRange, p.category)
        }
        
        // 1. ML TRIGGER LOG
        let triggerMsg = "Heard: \(label) (Conf: \(String(format: "%.2f", confidence)))"
        await PerformanceLogger.shared.logTelemetry(step: "1_ML_TRIGGER", message: triggerMsg)
        
        // --- NEW: THE MUSIC STATE TRIGGER ---
        let isMusic = label.lowercased() == "music"
        if isMusic {
            lastMusicDetectedTime = now
            
            // If this is a BRAND NEW music event, wake up the Shazam search!
            if !isMusicCurrentlyPlaying {
                isMusicCurrentlyPlaying = true
                hasMatchedCurrentSong = false // Unlock the search
                self.signatureGenerator = SHSignatureGenerator() // Fresh bucket
                self.accumulatedFrames = 0
                //print("🎵 Radar detected music. Waking up Shazam...")
            }
        }
        
        guard let buffer = latestBuffer, let channelData = buffer.floatChannelData else { return }
        
        // --- THE CRASH FIX: Dynamically size the read buffer to prevent EXC_BAD_ACCESS ---
        let safeCount = min(Int(buffer.frameLength), 4096)
        
        let peak = Array(UnsafeBufferPointer(start: channelData[0], count: safeCount)).map(abs).max() ?? 0.0
        
        // 2. VOLUME GATE
        let minimumPeak: Float = isVehicle ? 0.02 : 0.04
        guard peak > minimumPeak else { return }
        
        // 3. FFT HANDLING
        var targets = self.fftProcessor.analyzeMultiple(samples: Array(UnsafeBufferPointer(start: channelData[0], count: safeCount)), sampleRate: self.sampleRate, maxPeaks: 3)
        
        if isVehicle {
            targets = [(frequency: 100.0, confidence: Float(confidence))]
        } else if targets.isEmpty {
            return
        }
        
        let localSampleRate = self.sampleRate
        let exactMicDistance = await HardwareCalibration.micBaseline
        
        // --- NEW: CALCULATE BEARING BEFORE MATCHING ---
        let currentBearing: Double
        if buffer.format.channelCount >= 2 {
            currentBearing = self.fftProcessor.calculateTDOA(
                left: Array(UnsafeBufferPointer(start: channelData[0], count: safeCount)),
                right: Array(UnsafeBufferPointer(start: channelData[1], count: safeCount)),
                sampleRate: localSampleRate,
                micDistance: exactMicDistance
            ) ?? 0.0
        } else {
            currentBearing = 0.0
        }
        
        activeThreats.removeAll { now.timeIntervalSince($0.lastSeen) > 4.0 }
        
        for target in targets {
            let currentFreq = target.frequency
            var matchIndex: Int? = nil
            
            // THREAT MATCHING
            for (index, threat) in activeThreats.enumerated() {
                guard threat.category.rawValue == currentCategory.rawValue else { continue }
                
                if isVehicle {
                    // THE FIX: Separate cars by spatial angle instead of frequency
                    let bearingDiff = abs(threat.lastBearing - currentBearing)
                    let normalizedDiff = bearingDiff > 180 ? 360 - bearingDiff : bearingDiff
                    
                    // If the new car is within 35 degrees of the old car, keep the ID
                    if normalizedDiff < 35.0 {
                        matchIndex = index
                        break
                    }
                } else {
                    // Standard frequency matching for sirens, music, and birds
                    let threshold = isMusic ? 8000.0 : 40.0
                    if abs(threat.lastFrequency - currentFreq) < threshold {
                        matchIndex = index
                        break
                    }
                }
            }
            
            let threatSessionID: UUID
            let dopplerResult: (isApproaching: Bool, shiftHz: Double)?
            
            if let index = matchIndex {
                activeThreats[index].lastFrequency = currentFreq
                activeThreats[index].lastBearing = currentBearing // Update bearing
                activeThreats[index].lastSeen = now
                
                if isVehicle || isMusic {
                    dopplerResult = nil
                } else {
                    dopplerResult = activeThreats[index].dopplerTracker.update(with: currentFreq, confidence: target.confidence)
                }
                threatSessionID = activeThreats[index].sessionID
            } else {
                let newID = UUID()
                var newTracker = SirenDopplerTracker()
                dopplerResult = newTracker.update(with: currentFreq, confidence: target.confidence)
                
                activeThreats.append(ActiveThreat(
                    sessionID: newID,
                    dopplerTracker: newTracker,
                    lastFrequency: currentFreq,
                    lastBearing: currentBearing, // Save bearing
                    lastSeen: now,
                    category: currentCategory
                ))
                threatSessionID = newID
            }
            
            // 4. DISTANCE MATH ONLY (Task.detached)
            Task.detached(priority: .userInitiated) { [weak self, threatSessionID, currentBearing] in
                guard let self = self else { return }
                
                let ambientFloor: Double = isVehicle ? 0.02 : 0.04
                let safePeak = min(max(Double(peak), ambientFloor), profileCeiling)
                let linearRatio = (profileCeiling - safePeak) / (profileCeiling - ambientFloor)
                
                let adjustedMaxRange = isVehicle ? 400.0 : profileMaxRange
                let curvePower = isVehicle ? 2.2 : 2.5
                let estimatedFeet = max(10.0, pow(linearRatio, curvePower) * adjustedMaxRange)
                let normalizedUI_Distance = estimatedFeet / 1000.0
                
                let newEvent = SoundEvent(
                    sessionID: threatSessionID,
                    timestamp: Date(),
                    threatLabel: label,
                    confidence: confidence,
                    bearing: currentBearing, // Use the angle we already calculated
                    distance: normalizedUI_Distance,
                    energy: Float(safePeak),
                    dopplerRate: dopplerResult?.shiftHz != nil ? Float(dopplerResult!.shiftHz) : nil,
                    isApproaching: dopplerResult?.isApproaching ?? false,
                    latitude: nil,
                    longitude: nil
                )
                
                await MainActor.run { _ = self.continuation.yield(newEvent) }
            }
        }
    }
    
    func setupAnalyzer(format: AVAudioFormat) throws {
        self.sampleRate = format.sampleRate
        
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
                
                // --- THE WIND & NOISE FILTER ---
                // Block the ML from hallucinating these sounds when wind hits the mic
                // let ignoredLabels = ["fire", "thunderstorm", "wind", "breathing", "burp", "snore"]
                // if ignoredLabels.contains(label) { continue }
                
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
            print("🎵 Shazam: Listening... no match yet.")
        }
    }
}
