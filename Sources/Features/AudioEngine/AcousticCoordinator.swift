import Foundation
import Accelerate
import AVFoundation

// FIX: Add Final and Sendable to allow background processing
final class AcousticCoordinator: Sendable {
    private let fftProcessor = FFTProcessor(sampleCount: 4096)
    private let tdoaProcessor = TDOAProcessor()
    
    // We'll remove the history array for now to ensure strict Sendable compliance
    // without needing complex synchronization.
    
    func processBuffer(_ buffer: AVAudioPCMBuffer, classification: String, confidence: Double) -> SoundEvent {
        var rms: Float = 0
        if let data = buffer.floatChannelData?[0] {
            vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        }
        
        let decibels = 20 * log10(max(Double(rms), 0.000001))
        let currentFreq = fftProcessor.analyze(buffer: buffer)
        let currentAngle = tdoaProcessor.calculateAngle(buffer: buffer)
        
        let normalized = (decibels + 100) / 100
        let proximity = max(0.0, min(1.0, 1.0 - normalized))

        return SoundEvent(
            timestamp: Date(),
            classification: classification,
            confidence: Float(confidence),
            angle: currentAngle,
            proximity: proximity,
            decibels: Float(decibels),
            frequency: currentFreq
        )
    }
}
