import Foundation
import Accelerate
import AVFoundation

final class FFTProcessor: Sendable {
    private let sampleCount: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    
    init(sampleCount: Int) {
        // sampleCount should be a power of 2 (e.g., 1024 or 4096)
        self.log2n = vDSP_Length(log2(Double(sampleCount)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.sampleCount = sampleCount
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    func analyze(buffer: AVAudioPCMBuffer) -> Double {
        let frameCount = Int(buffer.frameLength)
        let n = frameCount / 2
        
        // 1. Prepare Complex Buffers
        var realp = [Float](repeating: 0, count: n)
        var imagp = [Float](repeating: 0, count: n)
        var output = DSPSplitComplex(realp: &realp, imagp: &imagp)
        
        // 2. Convert Audio to Complex Split Format
        let windowedBuffer = [Float](repeating: 0, count: frameCount)
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        
        channelData.withMemoryRebound(to: DSPComplex.self, capacity: n) { 
            vDSP_ctoz($0, 2, &output, 1, vDSP_Length(n))
        }
        
        // 3. Perform the Forward FFT
        vDSP_fft_zrip(fftSetup, &output, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // 4. Find the Peak Magnitude
        var magnitudes = [Float](repeating: 0, count: n)
        vDSP_zvmags(&output, 1, &magnitudes, 1, vDSP_Length(n))
        
        var maxMagnitude: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(&magnitudes, 1, &maxMagnitude, &maxIndex, vDSP_Length(n))
        
        // 5. Convert Index to Frequency (Hz)
        let sampleRate = buffer.format.sampleRate
        let frequency = Double(maxIndex) * (sampleRate / Double(frameCount))
        
        return frequency
    }
}
