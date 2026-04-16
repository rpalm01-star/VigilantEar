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
    
    // MARK: - Doppler State Tracking
    private var dopplerFrequencyBuffer: [Double] = []
    private let maxDopplerBufferSize = 40
    private var dopplerBaselineCenter: Double?
    
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var resultsObserver: ThreatResultsObserver?
    
    private var latestBuffer: AVAudioPCMBuffer?
    private var latestTime: AVAudioTime?
    
    private var lastKnownLocation: CLLocationCoordinate2D? = nil
    
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
        
        // Feed ML continuously - removed the "Acoustic Event" volume gate!
        streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
    }
    
    func confirmThreatAndTrack(label: String) {
        guard let buffer = latestBuffer,
              let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let leftSamples = Array(UnsafeBufferPointer(start: channelData[0], count: min(frameLength, 4096)))
        let rightSamples = Array(UnsafeBufferPointer(start: channelData[1], count: min(frameLength, 4096)))
        
        let peak = leftSamples.map(abs).max() ?? 0.0
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // --- 1. INVERSE SQUARE LAW DISTANCE CALIBRATION ---
            // Establish the Acoustic Floor and Ceiling
            let ambientFloor: Double = 0.01
            let clippingCeiling: Double = 0.95
            
            // Clamp the raw peak to prevent math crashes
            let safePeak = min(max(Double(peak), ambientFloor), clippingCeiling)
            
            // Logarithmic Scaling
            let linearRatio = (clippingCeiling - safePeak) / (clippingCeiling - ambientFloor)
            let exponentialCurve = pow(linearRatio, 3.0)
            
            // Map to the true Radar Horizon (1,000 feet)
            let radarHorizonInFeet = 1000.0
            let estimatedFeet = max(5.0, exponentialCurve * radarHorizonInFeet)
            
            // Normalize for the UI (1.0 = 1,000 feet)
            let normalizedDistance = estimatedFeet / radarHorizonInFeet
            
            // --- 2. TDOA BEARING CALCULATION ---
            var angle = self.fftProcessor.calculateTDOA(left: leftSamples, right: rightSamples, sampleRate: self.sampleRate) ?? 0.0
            
            // --- 3. HARDWARE POLARITY FIX ---
            // If the user flips the phone so the notch is on the left, the Left and Right
            // microphones are physically swapped. We must invert the math to match.
            let orientation = await MainActor.run { UIDevice.current.orientation }
            if orientation == .landscapeLeft {
                angle *= -1.0
            }
            
            // 1. SYNCHRONOUS READ: Grab the actor's state into local constants first!
            let currentLat = await lastKnownLocation?.latitude
            let currentLon = await lastKnownLocation?.longitude
            
            // 2. BUILD THE COPY: Create the struct before crossing any thread boundaries
            let newEvent = SoundEvent(
                threatLabel: label,
                bearing: angle,
                distance: normalizedDistance,
                energy: Float(peak),
                latitude: currentLat,
                longitude: currentLon
            )
            
            // 3. FIRE AND FORGET: Now it is safe to hand the finished copy to the background
            Task.detached(priority: .background) {
                await CloudLogger.shared.logEvent(newEvent)
            }
            
            // 4. UI UPDATE
            _ = await MainActor.run {
                self.continuation.yield(newEvent)
            }
        }
    }
    
    func setupAnalyzer(format: AVAudioFormat) throws {
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 1000)
        request.overlapFactor = 0.9 // This is the "Rapid Fire" fix
        
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
        
        if topClassification.confidence > 0.70 {
            let label = topClassification.identifier.lowercased()
            Task {
                await pipeline?.confirmThreatAndTrack(label: label)
            }
        }
    }
}
