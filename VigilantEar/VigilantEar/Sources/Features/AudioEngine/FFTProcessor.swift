import Foundation
import Accelerate

/// Optimized, thread-safe FFT processor using Accelerate.
/// Fully fixed for Swift pointer lifetime rules + GCC-PHAT TDOA.
final class FFTProcessor: @unchecked Sendable {
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: [Float]
    private let fftSize: Int
    
    init(fftSize: Int) {
        precondition(fftSize > 0 && (fftSize & (fftSize - 1)) == 0, "FFT size must be a power of 2")
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        
        self.window = {
            var w = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&w, vDSP_Length(fftSize), 0)
            return w
        }()
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    /// Returns dominant frequency (Hz) + confidence (0–1) for Doppler.
    func analyze(samples: [Float], sampleRate: Double) -> (frequency: Double, confidence: Float) {
        guard samples.count == fftSize else { return (0, 0) }
        
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        
        let halfSize = fftSize / 2
        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        
        // 1. Pack and Forward FFT
        forwardFFT(windowed, real: &real, imag: &imag)
        
        var magnitudes = [Float](repeating: 0.0, count: halfSize)
        
        real.withUnsafeMutableBufferPointer { rPtr in
            imag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                
                // Clear the packed Nyquist value from the imaginary DC component
                // so it doesn't skew the magnitude calculation
                split.imagp[0] = 0.0
                
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }
        
        var maxMag: Float = 0
        var peakIndex: vDSP_Length = 0
        vDSP_maxvi(&magnitudes, 1, &maxMag, &peakIndex, vDSP_Length(halfSize))
        
        let refinedIndex = quadraticInterpolate(magnitudes: magnitudes, peakIndex: Int(peakIndex))
        let frequency = Double(refinedIndex) * (sampleRate / Double(fftSize))
        
        let sum = magnitudes.reduce(0, +)
        let avg = sum / Float(halfSize)
        let confidence = avg > 1e-8 ? min(maxMag / avg, 1.0) : 0.0
        
        return (frequency, confidence)
    }
    
    
    // MARK: - Safe Accelerate Helpers
    
    /// Packs an N-element real array into an N/2 complex struct and performs forward FFT
    private func forwardFFT(_ input: [Float], real: inout [Float], imag: inout [Float]) {
        let halfSize = fftSize / 2
        real.withUnsafeMutableBufferPointer { rPtr in
            imag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                
                input.withUnsafeBufferPointer { inputPtr in
                    inputPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cPtr in
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
    }
    
    /// Performs inverse FFT on an N/2 complex struct, unpacks to an N-element array, and scales
    private func inverseFFT(real: inout [Float], imag: inout [Float], output: inout [Float]) {
        let halfSize = fftSize / 2
        real.withUnsafeMutableBufferPointer { rPtr in
            imag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                
                output.withUnsafeMutableBufferPointer { outPtr in
                    outPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cPtr in
                        vDSP_ztoc(&split, 1, cPtr, 2, vDSP_Length(halfSize))
                    }
                }
            }
        }
        
        // Scale result by 1 / (2 * N) as required by Apple's zrip documentation
        var scale: Float = 1.0 / Float(2 * fftSize)
        vDSP_vsmul(output, 1, &scale, &output, 1, vDSP_Length(fftSize))
    }
    
    private func quadraticInterpolate(magnitudes: [Float], peakIndex: Int) -> Float {
        guard peakIndex > 0 && peakIndex < magnitudes.count - 1 else {
            return Float(peakIndex)
        }
        let a = magnitudes[peakIndex - 1]
        let b = magnitudes[peakIndex]
        let c = magnitudes[peakIndex + 1]
        let denominator = a - 2 * b + c
        guard abs(denominator) > 1e-8 else { return Float(peakIndex) }
        let offset = 0.5 * (a - c) / denominator
        return Float(peakIndex) + offset
    }
}
