import Foundation
import AVFoundation
import Observation

@Observable
class MicrophoneManager {
    private let audioEngine = AVAudioEngine()
    var currentDecibels: Float = -160.0
    
    // New: Stubs for your Doppler and TDOA math
    var estimatedFrequency: Double = 0.0
    var estimatedAngle: Double = 0.0

    init() {
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install a 'tap' to get raw buffers 10 times a second
        inputNode.installTap(onBus: 0, bufferSize: 4410, format: recordingFormat) { (buffer, time) in
            self.analyzeBuffer(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            print("Audio Engine failed to start: \(error)")
        }
    }

    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        // 1. Calculate Decibels
        let frameLength = UInt32(buffer.frameLength)
        if let data = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<Int(frameLength) {
                sum += data[i] * data[i]
            }
            let rms = sqrt(sum / Float(frameLength))
            self.currentDecibels = 20 * log10(rms)
        }

        // 2. TODO: Insert FFT logic for Doppler Effect (Frequency Shift)
        
        // 3. TODO: Insert Phase Analysis for TDOA (Angle of Arrival)
    }
}
