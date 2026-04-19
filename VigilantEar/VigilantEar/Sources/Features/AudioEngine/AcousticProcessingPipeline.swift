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
        await MainActor.run {
            PerformanceLogger.shared.logTelemetry(step: "1_ML_TRIGGER", message: "Heard: \(label) (Conf: \(String(format: "%.2f", confidence)))")
        }
        
        guard let buffer = latestBuffer, let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let leftSamples = Array(UnsafeBufferPointer(start: channelData[0], count: min(frameLength, 4096)))
        let rightSamples = Array(UnsafeBufferPointer(start: channelData[1], count: min(frameLength, 4096)))
        
        let peak = leftSamples.map(abs).max() ?? 0.0
        
        let isVehicle = label.contains("car") || label.contains("traffic") || label.contains("engine")
        let minimumPeak: Float = isVehicle ? 0.02 : 0.15
        
        // TRIPWIRE 2: The Volume Gate
        guard peak > minimumPeak else {
            await MainActor.run {
                PerformanceLogger.shared.logTelemetry(step: "2_VOLUME_DROP", message: "Peak \(String(format: "%.3f", peak)) failed to pass \(minimumPeak)")
            }
            return
        }
        
        var targets = self.fftProcessor.analyzeMultiple(samples: leftSamples, sampleRate: self.sampleRate, maxPeaks: 3)
        
        // TRIPWIRE 3: The FFT Fallback
        if targets.isEmpty {
            if isVehicle {
                targets.append((frequency: 100.0, confidence: Float(confidence)))
                await MainActor.run {
                    PerformanceLogger.shared.logTelemetry(step: "3_FFT_FALLBACK", message: "Injected 100Hz broadband fallback")
                }
            } else {
                await MainActor.run {
                    PerformanceLogger.shared.logTelemetry(step: "3_FFT_DROP", message: "No targets, not a vehicle. Dropped.")
                }
                return
            }
        } else {
            let baseTarget = targets[0]
            let baseTargetsCount = targets.count
            await MainActor.run {
                PerformanceLogger.shared.logTelemetry(step: "3_FFT_SUCCESS", message: "Found \(baseTargetsCount) targets. Top: \(String(format: "%.1f", baseTarget.frequency))Hz")
            }
        }
        
        activeThreats.removeAll { now.timeIntervalSince($0.lastSeen) > 1.5 }
        
        for target in targets {
            let currentFreq = target.frequency
            let currentConf = target.confidence
            
            var matchIndex: Int? = nil
            for (index, threat) in activeThreats.enumerated() {
                if abs(threat.lastFrequency - currentFreq) < 40.0 { matchIndex = index; break }
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
            
            await MainActor.run {
                PerformanceLogger.shared.logTelemetry(step: "4_MATH_START", message: "Sending to GCC-PHAT. Session: \(capturedThreatSessionID.uuidString.prefix(4))")
            }
            
            Task.detached(priority: .userInitiated) { [weak self, capturedThreatSessionID] in
                guard let self = self else { return }
                
                // --- 1. ACOUSTIC PROFILING & DISTANCE CALIBRATION ---
                // THE FIX: Lower the mathematical floor for vehicles so they plot correctly on the UI!
                let isVehicle = label.contains("car") || label.contains("traffic") || label.contains("engine")
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
                await MainActor.run {
                    let m = "Session: \(capturedThreatSessionID.uuidString.prefix(4)) 📏 [Distance Profiler] Type: \(label) | Ceiling: \(clippingCeiling) | Max Range: \(maxRangeInFeet)ft"
                    PerformanceLogger.shared.logTelemetry(step: "5_TELEMETRY DISTANCE PROFILER", message: m)
                }
                await MainActor.run {
                    let m = "Session: \(capturedThreatSessionID.uuidString.prefix(4)) 📏 [Distance] Est Feet: \(String(format: "%.1f", estimatedFeet))ft | UI Normalized: \(String(format: "%.3f", normalizedUI_Distance))"
                    PerformanceLogger.shared.logTelemetry(step: "5_TELEMETRY DISTANCE FEET", message: m)
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
                await MainActor.run {
                    let m = "Session: \(capturedThreatSessionID.uuidString.prefix(4)) 📏 [Bearing] Raw TDOA: \(String(format: "%.1f", rawAngle))° | Polarity Fixed: \(String(format: "%.1f", capturedAngle))"
                    PerformanceLogger.shared.logTelemetry(step: "5_TELEMETRY BEARING MATH", message: m)
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
        
        var detectedLabel: String?
        var highestConfidence: Double = 0.0
        
        // THE FIX: Scan the top 5 sounds, not just the 1st!
        for classification in classificationResult.classifications.prefix(5) {
            let label = classification.identifier.lowercased()
            let conf = classification.confidence
            
            // PRIORITY 1: Emergencies (Siren, Fire, Ambulance).
            // Even if it's hiding in the background at 25%, grab it immediately!
            if (label.contains("siren") || label.contains("fire") || label.contains("ambulance")) && conf > 0.25 {
                detectedLabel = label
                highestConfidence = conf
                break // Stop looking, this overrides everything
            }
            
            // PRIORITY 2: Vehicles (Car, Traffic, Engine).
            // Tire roar is a background wash. If it's in the top 5 at 20%+, grab it!
            if (label.contains("car") || label.contains("traffic") || label.contains("engine")) && conf > 0.20 {
                detectedLabel = label
                highestConfidence = conf
                break
            }
        }
        
        // PRIORITY 3: The standard fallback.
        // If we didn't find a hidden car or siren, just use whatever is loudest (if > 50%)
        if detectedLabel == nil, let top = classificationResult.classifications.first, top.confidence > 0.50 {
            detectedLabel = top.identifier.lowercased()
            highestConfidence = top.confidence
        }
        
        // If we found something worth tracking, send it to the pipeline
        if let finalLabel = detectedLabel {
            Task {
                await pipeline?.confirmThreatAndTrack(label: finalLabel, confidence: highestConfidence)
            }
        }
    }
}
