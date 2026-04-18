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
    
    func confirmThreatAndTrack(label: String, confidence: Double) {
        guard let buffer = latestBuffer,
              let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let leftSamples = Array(UnsafeBufferPointer(start: channelData[0], count: min(frameLength, 4096)))
        let rightSamples = Array(UnsafeBufferPointer(start: channelData[1], count: min(frameLength, 4096)))
        
        let peak = leftSamples.map(abs).max() ?? 0.0
        guard peak > 0.15 else { return }
        
        // 1. Scan for multiple cars simultaneously!
        let targets = self.fftProcessor.analyzeMultiple(samples: leftSamples, sampleRate: self.sampleRate, maxPeaks: 3)
        guard !targets.isEmpty else { return }
        
        let now = Date()
        // 2. Prune old cars that drove away more than 1.5 seconds ago
        activeThreats.removeAll { now.timeIntervalSince($0.lastSeen) > 1.5 }
        
        // 3. Process every car we just heard
        for target in targets {
            let currentFreq = target.frequency
            let currentConf = target.confidence
            
            var matchIndex: Int? = nil
            
            // Does this frequency match a car we are already tracking? (Allow +/- 40Hz for Doppler shifts)
            for (index, threat) in activeThreats.enumerated() {
                if abs(threat.lastFrequency - currentFreq) < 40.0 {
                    matchIndex = index
                    break
                }
            }
            
            var threatSessionID: UUID
            var dopplerResult: (isApproaching: Bool, shiftHz: Double)?
            
            if let index = matchIndex {
                // UPDATE EXISTING CAR
                activeThreats[index].lastFrequency = currentFreq
                activeThreats[index].lastSeen = now
                dopplerResult = activeThreats[index].dopplerTracker.update(with: currentFreq, confidence: currentConf)
                threatSessionID = activeThreats[index].sessionID
            } else {
                // SPAWN NEW CAR
                let newID = UUID()
                var newTracker = SirenDopplerTracker()
                dopplerResult = newTracker.update(with: currentFreq, confidence: currentConf)
                
                let newThreat = ActiveThreat(sessionID: newID, dopplerTracker: newTracker, lastFrequency: currentFreq, lastSeen: now)
                activeThreats.append(newThreat)
                threatSessionID = newID
                print("🚘 [MTT] Spawning New Target Tracking ID: \(newID.uuidString.prefix(4)) at \(String(format: "%.1f", currentFreq))Hz")
            }
            
            print("\n🚨 --- NEW THREAT DETECTED ---")
            print("🧠 [CoreML] Label: \(label) | Confidence: \(String(format: "%.2f", confidence))")
            print("📈 [Doppler] Freq: \(String(format: "%.1f", peak))Hz | Shift: \(String(format: "%.1f", dopplerResult?.shiftHz ?? 0.0))")
            
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                
                // --- 1. ACOUSTIC PROFILING & DISTANCE CALIBRATION ---
                let ambientFloor: Double = 0.15
                
                // We safely hop to the main thread for a microsecond to grab the UI/Physics profile.
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
                print("📏 [Distance Profiler] Type: \(label) | Ceiling: \(clippingCeiling) | Max Range: \(maxRangeInFeet)ft")
                print("📏 [Distance] Est Feet: \(String(format: "%.1f", estimatedFeet)) ft | UI Normalized: \(String(format: "%.3f", normalizedUI_Distance))")
                
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
                
                // 🐞 TELEMETRY: Bearing Math
                print("🧭 [Bearing] Raw TDOA: \(String(format: "%.1f", rawAngle))° | Polarity Fixed: \(String(format: "%.1f", angle))")
                
                // SYNCHRONOUS READ
                let currentLat = await lastKnownLocation?.latitude
                let currentLon = await lastKnownLocation?.longitude
                
                // BUILD THE EVENT
                let newEvent = SoundEvent(
                    sessionID: threatSessionID, // THE FIX: Assign it to the specific tracked car!
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
                                
                print("✅ [Dispatch] Sending to Radar & Cloud...")
                print("------------------------------")
                
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
        guard let topClassification = classificationResult.classifications.first else { return }
        
        // THE FIX: Lowered from 0.70 to 0.50 to catch continuous "acoustic wash" like traffic!
        if topClassification.confidence > 0.50 {
            let label = topClassification.identifier.lowercased()
            Task {
                await pipeline?.confirmThreatAndTrack(label: label, confidence: topClassification.confidence)
            }
        }
    }
    
}
