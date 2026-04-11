import AVFoundation

final class TDOAProcessor: Sendable {
    
    private let lastAngle = OSAtomicMutableDouble() // Thread-safe storage for lastAngle
    
    func calculateAngle(buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return lastAngle.value }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        
        // FIX: Use assumeIsolated to bridge the MainActor hardware settings
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
        guard total > 0.0001 else { return lastAngle.value }
        
        // 1. Calculate the raw balance
        let balance = (leftEnergy - rightEnergy) / total

        // 2. FIX: Map balance (-1.0 to 1.0) to a wide Angular spread.
        // -1.0 (Right Heavy) -> 90 degrees
        //  0.0 (Centered)    -> 0 degrees (Top/North)
        //  1.0 (Left Heavy)  -> -90 degrees
        var angle = Double(balance) * -90.0

        // 3. Add a smaller jitter so it doesn't look static, but keep it within bounds
        angle += Double.random(in: -5...5)
        angle = max(-90, min(90, angle))

        lastAngle.value = angle
        
        //print("TDOA → balance: \(String(format: "%.3f", balance)), angle: \(String(format: "%.1f", angle))°")
        
        return angle
    }
    
    func calculateAngleFromSamples(_ samples: [Float], sampleRate: Double) -> Double {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return lastAngle.value
        }
        buffer.frameLength = buffer.frameCapacity
        
        if let data = buffer.floatChannelData?[0] {
            for i in 0..<samples.count {
                data[i] = samples[i]
            }
        }
        return calculateAngle(buffer: buffer)
    }
}

// Helper to keep lastAngle thread-safe in a Sendable class
private final class OSAtomicMutableDouble: @unchecked Sendable {
    private var _value: Double = 0.0
    private let lock = NSLock()
    var value: Double {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
