import Foundation
import AVFoundation

class AcousticCoordinator {
    private let fftProcessor = FFTProcessor(sampleCount: 4096)
    private let tdoaProcessor = TDOAProcessor()
    
    // Sliding window to track frequency change (Doppler)
    private var frequencyHistory: [Double] = []
    private let maxHistory = 10 

    func processBuffer(_ buffer: AVAudioPCMBuffer, classification: String, confidence: Double) -> SoundEvent {
        // 1. Run the Physics
        let currentFreq = fftProcessor.analyze(buffer: buffer)
        let currentAngle = tdoaProcessor.calculateAngle(buffer: buffer)
        
        // 2. Calculate Decibels (RMS)
        var decibels: Float = -160.0
        if let data = buffer.floatChannelData?[0] {
            var rms: Float = 0
            vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
            decibels = 20 * log10(max(rms, 0.000001))
        }

        // 3. Track Doppler Shift (f_now vs f_average)
        frequencyHistory.append(currentFreq)
        if frequencyHistory.count > maxHistory { frequencyHistory.removeFirst() }
        
        // 4. Construct the Event
        return SoundEvent(
            id: UUID(),
            timestamp: Date(),
            decibels: decibels,
            frequency: currentFreq,
            confidence: confidence,
            classification: classification,
            angle: currentAngle
        )
    }
}
