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
        
        // TRIPWIRE 1: Did CoreML trigger?
        self.logStep = "1_ML_TRIGGER"
        self.logMessage = "Heard: \(label) (Conf: \(String(format: "%.2f", confidence)))"
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await PerformanceLogger.shared.logTelemetry(step: self.logStep, message: self.logMessage)
        }
        
        guard let buffer = latestBuffer, let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let leftSamples = Array(UnsafeBufferPointer(start: channelData[0], count: min(frameLength, 4096)))
        let rightSamples = Array(UnsafeBufferPointer(start: channelData[1], count: min(frameLength, 4096)))
        
        let peak = leftSamples.map(abs).max() ?? 0.0
        
        let isVehicle = await SoundProfile.classify(label).isVehicle
        let minimumPeak: Float = isVehicle ? 0.02 : 0.15
        
        // TRIPWIRE 2: The Volume Gate
        guard peak > minimumPeak else {
            // TRIPWIRE 1: Did CoreML trigger?
            self.logStep = "2_VOLUME_DROP"
            self.logMessage = "Peak \(String(format: "%.3f", peak)) failed to pass \(minimumPeak)"
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                await PerformanceLogger.shared.logTelemetry(step: self.logStep, message: self.logMessage)
            }
            return
        }
        
        var targets = self.fftProcessor.analyzeMultiple(samples: leftSamples, sampleRate: self.sampleRate, maxPeaks: 3)
        
        // TRIPWIRE 3: The FFT Fallback
        if targets.isEmpty {
            if isVehicle {
                targets.append((frequency: 100.0, confidence: Float(confidence)))
                self.logStep = "3_FFT_FALLBACK"
                self.logMessage = "Injected 100Hz broadband fallback"
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self = self else { return }
                    await PerformanceLogger.shared.logTelemetry(step: self.logStep, message: self.logMessage)
                }
            } else {
                self.logStep = "3_FFT_DROP"
                self.logMessage = "No targets, not a vehicle. Dropped."
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self = self else { return }
                    await PerformanceLogger.shared.logTelemetry(step: self.logStep, message: self.logMessage)
                }
                return
            }
        } else {
            let baseTarget = targets[0]
            let baseTargetsCount = targets.count
            self.logStep = "3_FFT_SUCCESS"
            self.logMessage = "Found \(baseTargetsCount) targets. Top: \(String(format: "%.1f", baseTarget.frequency)) Hz"
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                await PerformanceLogger.shared.logTelemetry(step: self.logStep, message: self.logMessage)
            }
        }
        
        activeThreats.removeAll { now.timeIntervalSince($0.lastSeen) > 1.5 }
        
        for target in targets {
            let currentFreq = target.frequency
            let currentConf = target.confidence
            
            var matchIndex: Int? = nil
            
            let isVehicle = await SoundProfile.classify(label).isVehicle
            
            for (index, threat) in activeThreats.enumerated() {
                // THE FIX: If it's a vehicle, broadband frequency fluctuates wildly.
                // Don't use the strict 40Hz rule. If an active vehicle track exists, bind to it!
                if isVehicle {
                    matchIndex = index
                    break
                }
                // For tonal sirens, keep the strict 40Hz harmonic grouping
                else if abs(threat.lastFrequency - currentFreq) < 40.0 {
                    matchIndex = index
                    break
                }
            }
            
            var threatSessionID: UUID
            var dopplerResult: (isApproaching: Bool, shiftHz: Double)?
            
            if let index = matchIndex {
                activeThreats[index].lastFrequency = currentFreq
                activeThreats[index].lastSeen = now
                dopplerResult = activeThreats[index].dopplerTracker.update(with: currentFreq, confidence: currentConf)
                threatSessionID = activeThreats[index].sessionID
            } else {
                let newID = UUID()
                var newTracker = SirenDopplerTracker()
                dopplerResult = newTracker.update(with: currentFreq, confidence: currentConf)
                let newThreat = ActiveThreat(sessionID: newID, dopplerTracker: newTracker, lastFrequency: currentFreq, lastSeen: now)
                activeThreats.append(newThreat)
                threatSessionID = newID
            }
            
            let capturedThreatSessionID = threatSessionID
            self.logStep = "4_MATH_START"
            self.logMessage = "Sending to GCC-PHAT. Session: \(capturedThreatSessionID.uuidString.prefix(4))"
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                await PerformanceLogger.shared.logTelemetry(step: self.logStep, message: self.logMessage)
            }
            
            Task.detached(priority: .userInitiated) { [weak self, capturedThreatSessionID] in
                guard let self = self else { return }
                
                // --- 1. ACOUSTIC PROFILING & DISTANCE CALIBRATION ---
                // THE FIX: Lower the mathematical floor for vehicles so they plot correctly on the UI!
                let ambientFloor: Double = isVehicle ? 0.02 : 0.15
                
                let profile = await MainActor.run { SoundProfile.classify(label) }
                let clippingCeiling = profile.ceiling
                let maxRangeInFeet = profile.maxRange
                
                let safePeak = min(max(Double(peak), ambientFloor), clippingCeiling)
                let linearRatio = (clippingCeiling - safePeak) / (clippingCeiling - ambientFloor)
                let exponentialCurve = pow(linearRatio, 2.0)
                
                let estimatedFeet = max(5.0, exponentialCurve * maxRangeInFeet)
                let uiMapScaleInFeet = 1000.0
                let normalizedUI_Distance = estimatedFeet / uiMapScaleInFeet
                
                // 🐞 TELEMETRY: Distance Math
                var logStep = "TELEMETRY: Session: \(capturedThreatSessionID.uuidString.prefix(4))"
                var logMessage = "📏 [Distance Profiler] Type: \(label) | Ceiling: \(clippingCeiling) | Max Range: \(maxRangeInFeet)ft"
                let logMessage2 = "📏 [Distance] Est Feet: \(String(format: "%.1f", estimatedFeet))ft | UI Normalized: \(String(format: "%.3f", normalizedUI_Distance))"
                Task.detached(priority: .userInitiated) {
                    await PerformanceLogger.shared.logTelemetry(step: logStep, message: logMessage)
                    await PerformanceLogger.shared.logTelemetry(step: logStep, message: logMessage2)
                }
                
                // --- 2. TDOA BEARING CALCULATION ---
                // THE FIX: Actually use the HardwareCalibration value!
                let exactMicDistance = await HardwareCalibration.micBaseline
                
                let rawAngle = self.fftProcessor.calculateTDOA(
                    left: leftSamples,
                    right: rightSamples,
                    sampleRate: self.sampleRate,
                    micDistance: exactMicDistance // Injected here!
                ) ?? 0.0
                
                // --- 3. HARDWARE POLARITY FIX ---
                var angle = rawAngle
                let orientation = await MainActor.run { UIDevice.current.orientation }
                if orientation == .landscapeLeft {
                    angle *= -1.0
                }
                let capturedAngle = angle
                
                // 🐞 TELEMETRY: Bearing Math
                logStep = "6_TELEMETRY_BEARING_MATH: Session: \(capturedThreatSessionID.uuidString.prefix(4))"
                logMessage = "📏 [Bearing] Raw TDOA: \(String(format: "%.1f", rawAngle))° | Polarity Fixed: \(String(format: "%.1f", capturedAngle))"
                Task.detached(priority: .userInitiated) {
                    await PerformanceLogger.shared.logTelemetry(step: logStep, message: logMessage)
                }
                
                // SYNCHRONOUS READ
                let currentLat = await self.lastKnownLocation?.latitude
                let currentLon = await self.lastKnownLocation?.longitude
                
                // BUILD THE EVENT
                let newEvent = SoundEvent(
                    sessionID: capturedThreatSessionID, // THE FIX: Assign it to the specific tracked car!
                    timestamp: Date(),
                    threatLabel: label,
                    confidence: confidence,
                    bearing: angle,
                    distance: normalizedUI_Distance,
                    energy: Float(safePeak),
                    dopplerRate: dopplerResult?.shiftHz != nil ? Float(dopplerResult!.shiftHz) : nil,
                    isApproaching: dopplerResult?.isApproaching ?? false,
                    latitude: currentLat,
                    longitude: currentLon
                )
                
                // FIRE AND FORGET: Hand it to the cloud
                Task.detached(priority: .background) {
                    await CloudLogger.shared.logEvent(newEvent)
                }
                
                // UI UPDATE: Send to radar
                _ = await MainActor.run {
                    self.continuation.yield(newEvent)
                }
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
