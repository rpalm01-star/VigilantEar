import Accelerate
import AVFoundation
import Foundation

@MainActor
@Observable
final class AcousticCoordinator {
    
    var lastEvent: SoundEvent?
    
    private let tdoaProcessor = TDOAProcessor()
    private let fftProcessor: FFTProcessor
    private let hardwareCalibration = HardwareCalibration()
    
    // Injected from DependencyContainer
    var classificationService: ClassificationService?
    
    init() {
        // 4096 matches the buffer size used in MicrophoneManager
        self.fftProcessor = FFTProcessor(sampleCount: 4096)
    }
    
    func processBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) -> SoundEvent? {
        
        // 1. Calculate loudness (RMS → dB)
        var rms: Float = 0
        vDSP_rmsqv(buffer.floatChannelData?[0] ?? [], 1, &rms, vDSP_Length(buffer.frameLength))
        let db = 20 * log10(max(rms, 0.00001))
        
        // 2. Direction from TDOA
        let angle = tdoaProcessor.calculateAngle(from: buffer)
        
        // 3. Dominant frequency (for Doppler)
        let dominantFreq = fftProcessor.dominantFrequency(from: buffer)
        
        // 4. Real classification from SoundAnalysis
        let classification = classificationService?.currentClassification ?? "Unknown"
        let confidence = classificationService?.confidence ?? 0.0
        
        // 5. Proximity (0.0 = far, 1.0 = very close)
        let proximity = min(max((db - 60) / 40, 0.0), 1.0)
        
        // 6. Create event
        let event = SoundEvent(
            classification: classification,
            confidence: confidence,
            angle: angle,
            proximity: proximity
        )
        
        lastEvent = event
        return event
    }
}
