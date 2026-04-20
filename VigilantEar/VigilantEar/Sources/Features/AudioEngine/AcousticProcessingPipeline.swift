import AVFoundation
import Accelerate
import SoundAnalysis
import SwiftUI
import CoreLocation

actor AcousticProcessingPipeline {
    
    private let sampleRate: Double = 44100.0
    private let bufferSize: AVAudioFrameCount = 4096
    
    nonisolated let eventStream: AsyncStream<SoundEvent>
    private let continuation: AsyncStream<SoundEvent>.Continuation
    
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
        
        self.fftProcessor = FFTProcessor(fftSize: Int(self.bufferSize))
    }
    
    // Called by the MicrophoneManager whenever the GPS updates
    public func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        self.lastKnownLocation = coordinate
    }
    
    func processAudio(buffer: AVAudioPCMBuffer, time: AVAudioTime) async {
        self.latestBuffer = buffer
        self.latestTime = time
        
        // Feed ML continuously
        streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
    }
    
    func confirmThreatAndTrack(label: String, confidence: Double) async {
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) > 0.2 else { return }
        lastProcessTime = now
        
        let profile = await SoundProfile.classify(label)
        let isVehicle = await profile.isVehicle
        
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
            
            let threatSessionID: UUID
            let dopplerResult: (isApproaching: Bool, shiftHz: Double)?
            
            if let index = matchIndex {
                activeThreats[index].lastFrequency = currentFreq
                activeThreats[index].lastSeen = now
                dopplerResult = activeThreats[index].dopplerTracker.update(with: currentFreq, confidence: target.confidence)
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
                let safePeak = min(max(Double(peak), ambientFloor), profile.ceiling)
                let linearRatio = (profile.ceiling - safePeak) / (profile.ceiling - ambientFloor)
                
                // THE DISTANCE FIX
                let adjustedMaxRange = isVehicle ? 400.0 : profile.maxRange
                let curvePower = isVehicle ? 3.5 : 2.0
                let estimatedFeet = max(10.0, pow(linearRatio, curvePower) * adjustedMaxRange)
                let normalizedUI_Distance = estimatedFeet / 1000.0
                
                // BEARING FIX
                let exactMicDistance = await HardwareCalibration.micBaseline
                let rawAngle = self.fftProcessor.calculateTDOA(left: Array(UnsafeBufferPointer(start: channelData[0], count: 4096)),
                                                               right: Array(UnsafeBufferPointer(start: channelData[1], count: 4096)),
                                                               sampleRate: self.sampleRate,
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
                
                await MainActor.run { self.continuation.yield(newEvent) }
            }
        }
    }
    
    func setupAnalyzer(format: AVAudioFormat) throws {
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 1000)
        request.overlapFactor = 0.9
        
        let observer = ThreatResultsObserver(pipeline: self)
        self.resultsObserver = observer
        try streamAnalyzer?.add(request, withObserver: observer)
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
            var detectedLabel: String?
            var highestConfidence: Double = 0.0
            
            // THE FIX: Scan the top 5 sounds, not just the 1st!
            for (label, conf) in topCandidates {
                let isVehicle = SoundProfile.classify(label).isVehicle
                let isEmergency = SoundProfile.classify(label).isEmergency
                
                // PRIORITY 1: Emergencies (Siren, Fire, Ambulance).
                // Even if it's hiding in the background at 25%, grab it immediately!
                if isEmergency && conf > 0.5 {
                    detectedLabel = label
                    highestConfidence = conf
                    break // Stop looking, this overrides everything
                }
                if isVehicle && !isEmergency && conf > 0.20 {
                    detectedLabel = label
                    highestConfidence = conf
                    break
                }
            }
            // PRIORITY 3: The standard fallback.
            // If we didn't find a hidden car or siren, just use whatever is loudest (if > 50%)
            if detectedLabel == nil, let top = topCandidates.first, top.1 > 0.50 {
                detectedLabel = top.0
                highestConfidence = top.1
            }
            // If we found something worth tracking, send it to the pipeline
            if let finalLabel = detectedLabel {
                Task {
                    await self.pipeline?.confirmThreatAndTrack(label: finalLabel, confidence: highestConfidence)
                }
            }
        }
    }
}
