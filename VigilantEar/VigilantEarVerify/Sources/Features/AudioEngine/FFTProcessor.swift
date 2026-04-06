import Foundation
import Accelerate
import AVFoundation

/// Optimized, thread-safe FFT processor using stable Accelerate APIs.
final class FFTProcessor: @unchecked Sendable {
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    
    init(sampleCount: Int) {
        self.log2n = vDSP_Length(log2(Double(sampleCount)))
        // Create the setup once to save CPU cycles on the M4
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }
    
    // Clean up memory when the processor is destroyed
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    // FIX: Updated signature to match the call in AcousticCoordinator
        func analyze(samples: [Float], sampleRate: Double) -> Double {
            let nOver2 = samples.count / 2
            
            var real = [Float](repeating: 0.0, count: nOver2)
            var imag = [Float](repeating: 0.0, count: nOver2)
            
            return real.withUnsafeMutableBufferPointer { rPtr in
                imag.withUnsafeMutableBufferPointer { iPtr in
                    var splitComplex = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                    
                    // Pack real data into split complex format
                    samples.withUnsafeBytes { dataPtr in
                        let complexPtr = dataPtr.bindMemory(to: DSPComplex.self).baseAddress!
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(nOver2))
                    }
                    
                    // Perform the Forward FFT
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    
                    // Calculate magnitudes to find the peak
                    var magnitudes = [Float](repeating: 0.0, count: nOver2)
                    vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(nOver2))
                    
                    var maxMag: Float = 0
                    var maxIndex: vDSP_Length = 0
                    vDSP_maxvi(&magnitudes, 1, &maxMag, &maxIndex, vDSP_Length(nOver2))
                    
                    return Double(maxIndex) * (sampleRate / Double(samples.count))
                }
            }
        }
    }
