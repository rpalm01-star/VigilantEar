import Foundation
import Accelerate
import AVFoundation

class TDOAProcessor {
    private let micDistance = HardwareCalibration.micBaseline
    private let speedOfSound: Double = 343.0 // meters per second
    
    /// Calculates the Angle of Arrival (θ) in degrees
    func calculateAngle(buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData, buffer.format.channelCount >= 2 else {
            return 0.0
        }
        
        let frameCount = Int(buffer.frameLength)
        let mic1 = channelData[0] // Top Mic
        let mic2 = channelData[1] // Bottom Mic
        
        // 1. Cross-Correlation using Accelerate (vDSP_conv)
        var correlation = [Float](repeating: 0, count: frameCount)
        vDSP_conv(mic1, 1, mic2, 1, &correlation, 1, vDSP_Length(frameCount), vDSP_Length(frameCount))
        
        // 2. Find the index of the maximum correlation (The "Peak" delay)
        var maxCorr: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(&correlation, 1, &maxCorr, &maxIndex, vDSP_Length(frameCount))
        
        // 3. Convert Index to Time Delay (Δt)
        let delayInSamples = Double(maxIndex) - Double(frameCount / 2)
        let deltaTime = delayInSamples / buffer.format.sampleRate
        
        // 4. Geometry: θ = arccos((v * Δt) / d)
        let ratio = (speedOfSound * deltaTime) / micDistance
        
        // Clamp ratio to [-1, 1] to avoid NaN in acos
        let clampedRatio = max(-1.0, min(1.0, ratio))
        let angleRadians = acos(clampedRatio)
        
        return angleRadians * (180.0 / .pi) // Return in Degrees
    }
}
