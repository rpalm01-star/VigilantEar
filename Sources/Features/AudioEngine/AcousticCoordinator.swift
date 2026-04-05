import Foundation
import Accelerate
import AVFoundation

// FIX: Add Final and Sendable to allow background processing
final class AcousticCoordinator: Sendable {
    private let fftProcessor = FFTProcessor(sampleCount: 4096)
    private let tdoaProcessor = TDOAProcessor()
    
    // We'll remove the history array for now to ensure strict Sendable compliance
    // without needing complex synchronization.
    
    // FIX: Update to accept the raw [Float] array
        func processFromSamples(_ samples: [Float], sampleRate: Double, classification: String, confidence: Double) -> SoundEvent {
            // 1. Calculate Decibels using the raw array
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
            let decibels = 20 * log10(max(Double(rms), 0.000001))
            
            // 2. Run the Physics Processors (Ensure your FFT/TDOA accept [Float])
            let currentFreq = fftProcessor.analyze(samples: samples, sampleRate: sampleRate)
            
            // 3. Normalize for Radar UI
            let normalized = (decibels + 100) / 100
            let proximity = max(0.0, min(1.0, 1.0 - normalized))

            return SoundEvent(
                timestamp: Date(),
                classification: classification,
                confidence: Float(confidence),
                angle: 0.0, // Placeholder for TDOA logic
                proximity: proximity,
                decibels: Float(decibels),
                frequency: currentFreq
            )
        }
}
