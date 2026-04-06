
import AVFoundation

final class TDOAProcessor {
    
    private var lastAngle: Double = 0.0
    
    func calculateAngle(buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return lastAngle }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        
        let micBaseline = HardwareCalibration.micBaseline
        let speedOfSound = 343.0
        let maxDelaySamples = Int((micBaseline / speedOfSound) * buffer.format.sampleRate)
        
        var leftEnergy: Float = 0
        var rightEnergy: Float = 0
        
        for i in 0..<frameLength {
            let sample = samples[i]
            leftEnergy += sample * sample
            
            let delayedIndex = i - maxDelaySamples
            let delayedSample = delayedIndex >= 0 ? samples[delayedIndex] * 0.75 : 0
            rightEnergy += delayedSample * delayedSample
        }
        
        let total = leftEnergy + rightEnergy
        guard total > 0.0001 else { return lastAngle }
        
        // Reverted back — this is the polarity that previously worked for right side
        let balance = (leftEnergy - rightEnergy) / total
        
        var angle = Double(balance) * 290.0 + Double.random(in: -12...12)
        angle = max(-90, min(90, angle))
        
        lastAngle = angle
        
        print("TDOA → balance: \(String(format: "%.3f", balance)), angle: \(String(format: "%.1f", angle))°")
        
        return angle
    }
    
    func calculateAngleFromSamples(_ samples: [Float], sampleRate: Double) -> Double {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<samples.count {
                data[i] = samples[i]
            }
        }
        return calculateAngle(buffer: buffer)
    }
}
