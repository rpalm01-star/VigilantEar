import Foundation
import Accelerate
import AVFoundation

/// Optimized, thread-safe FFT processor using Accelerate.
/// Fully fixed for Swift pointer lifetime rules + GCC-PHAT TDOA (zero warnings).
final class FFTProcessor: @unchecked Sendable {
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: [Float]          // Precomputed Hann window
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
        
        var real = windowed
        var imag = [Float](repeating: 0.0, count: fftSize)
        
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        
        let nOver2 = fftSize / 2
        var magnitudes = [Float](repeating: 0.0, count: nOver2)
        
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(nOver2))
            }
        }
        
        var maxMag: Float = 0
        var peakIndex: vDSP_Length = 0
        vDSP_maxvi(&magnitudes, 1, &maxMag, &peakIndex, vDSP_Length(nOver2))
        
        let refinedIndex = quadraticInterpolate(magnitudes: magnitudes, peakIndex: Int(peakIndex))
        let frequency = Double(refinedIndex) * (sampleRate / Double(fftSize))
        
        let sum = magnitudes.reduce(0, +)
        let avg = sum / Float(nOver2)
        let confidence = avg > 1e-8 ? min(maxMag / avg, 1.0) : 0.0
        
        return (frequency, confidence)
    }
    
    /// GCC-PHAT TDOA between stereo channels (angle of arrival).
    func computeTDOA(left: [Float], right: [Float], sampleRate: Double) -> (delaySeconds: Double, confidence: Float)? {
        guard left.count == fftSize, right.count == fftSize else { return nil }
        
        // Window both channels
        var leftW = [Float](repeating: 0, count: fftSize)
        var rightW = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(left, 1, window, 1, &leftW, 1, vDSP_Length(fftSize))
        vDSP_vmul(right, 1, window, 1, &rightW, 1, vDSP_Length(fftSize))
        
        var leftReal = leftW
        var leftImag = [Float](repeating: 0, count: fftSize)
        var rightReal = rightW
        var rightImag = [Float](repeating: 0, count: fftSize)
        
        // FFT left
        leftReal.withUnsafeMutableBufferPointer { r in
            leftImag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        
        // FFT right
        rightReal.withUnsafeMutableBufferPointer { r in
            rightImag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        
        // Cross-spectrum: left * conj(right)
        var crossReal = [Float](repeating: 0, count: fftSize)
        var crossImag = [Float](repeating: 0, count: fftSize)
        
        leftReal.withUnsafeMutableBufferPointer { lr in
            leftImag.withUnsafeMutableBufferPointer { li in
                rightReal.withUnsafeMutableBufferPointer { rr in
                    rightImag.withUnsafeMutableBufferPointer { ri in
                        crossReal.withUnsafeMutableBufferPointer { cr in
                            crossImag.withUnsafeMutableBufferPointer { ci in
                                var leftSplit = DSPSplitComplex(realp: lr.baseAddress!, imagp: li.baseAddress!)
                                var rightSplit = DSPSplitComplex(realp: rr.baseAddress!, imagp: ri.baseAddress!)
                                var cross = DSPSplitComplex(realp: cr.baseAddress!, imagp: ci.baseAddress!)
                                vDSP_zvmul(&leftSplit, 1, &rightSplit, 1, &cross, 1, vDSP_Length(fftSize), -1)
                            }
                        }
                    }
                }
            }
        }
        
        // GCC-PHAT normalization
        for i in 0..<fftSize {
            let re = crossReal[i]
            let im = crossImag[i]
            let magnitude = sqrt(re * re + im * im) + 1e-12
            crossReal[i] = re / magnitude
            crossImag[i] = im / magnitude
        }
        
        // Inverse FFT
        crossReal.withUnsafeMutableBufferPointer { r in
            crossImag.withUnsafeMutableBufferPointer { i in
                var cross = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP_fft_zrip(fftSetup, &cross, 1, log2n, FFTDirection(kFFTDirection_Inverse))
            }
        }
        
        // Scale inverse FFT result by 1/N
        var scale: Float = 1.0 / Float(fftSize)
        crossReal.withUnsafeMutableBufferPointer { buffer in
            vDSP_vsmul(buffer.baseAddress!, 1, &scale, buffer.baseAddress!, 1, vDSP_Length(fftSize))
        }
        
        // Find peak lag on real part
        var maxCorr: Float = 0
        var lagIndex: vDSP_Length = 0
        vDSP_maxvi(&crossReal, 1, &maxCorr, &lagIndex, vDSP_Length(fftSize))
        
        let lag = Int(lagIndex) - fftSize / 2
        let delay = Double(lag) / sampleRate
        
        let totalEnergy = crossReal.reduce(0, +)
        let confidence = totalEnergy > 1e-8 ? maxCorr / (totalEnergy / Float(fftSize)) : 0.0
        
        guard abs(delay) < 0.001 else { return nil }
        return (delay, confidence)
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
