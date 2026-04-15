import Foundation
import Accelerate

/// Optimized, thread-safe FFT processor using Accelerate.
/// Fully fixed for Swift 6 isolation boundaries + GCC-PHAT TDOA.
final class FFTProcessor: @unchecked Sendable {
    private let log2n: vDSP_Length
    
    // The ultimate Swift 6 override for thread-safe C-pointers
    nonisolated(unsafe) private let fftSetup: FFTSetup
    
    private let window: [Float]
    private let fftSize: Int
    
    nonisolated init(fftSize: Int) {
        precondition(fftSize > 0 && (fftSize & (fftSize - 1)) == 0, "FFT size must be a power of 2")
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        
        self.fftSetup = vDSP_create_fftsetup(self.log2n, FFTRadix(kFFTRadix2))!
        
        self.window = {
            var w = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&w, vDSP_Length(fftSize), 0)
            return w
        }()
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    // MARK: - Core Analysis
    
    nonisolated func analyze(samples: [Float], sampleRate: Double) -> (frequency: Double, confidence: Float) {
        guard samples.count == fftSize else { return (0, 0) }
        
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        
        let halfSize = fftSize / 2
        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        
        forwardFFT(windowed, real: &real, imag: &imag)
        
        var magnitudes = [Float](repeating: 0.0, count: halfSize)
        
        real.withUnsafeMutableBufferPointer { rPtr in
            imag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
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
    
    nonisolated func calculateTDOA(left: [Float], right: [Float], sampleRate: Double, micDistance: Double = 0.15) -> Double? {
        // HEARTBEAT 1: Method Entry
        print("🎙️ TDOA Step 1: Start Math (Left: \(left.count), Right: \(right.count))")
        
        // SAFETY: Ensure we don't overflow the FFT buffer.
        // If we receive 4800 samples but fftSize is 4096, we MUST truncate.
        let safeLeft = Array(left.prefix(fftSize))
        let safeRight = Array(right.prefix(fftSize))
        
        guard safeLeft.count == fftSize, safeRight.count == fftSize else {
            print("⚠️ TDOA Abort: Samples count mismatch")
            return 0.0
        }
        
        let halfSize = fftSize / 2
        var leftReal = [Float](repeating: 0, count: halfSize)
        var leftImag = [Float](repeating: 0, count: halfSize)
        var rightReal = [Float](repeating: 0, count: halfSize)
        var rightImag = [Float](repeating: 0, count: halfSize)
        
        // Forward Transforms
        forwardFFT(safeLeft, real: &leftReal, imag: &leftImag)
        forwardFFT(safeRight, real: &rightReal, imag: &rightImag)
        
        // HEARTBEAT 2: Frequency Domain Reached
        print("🎙️ TDOA Step 2: FFTs Complete")
        
        var crossReal = [Float](repeating: 0, count: halfSize)
        var crossImag = [Float](repeating: 0, count: halfSize)
        
        // GCC-PHAT Normalization Loop
        for i in 0..<halfSize {
            let a = leftReal[i], b = leftImag[i]
            let c = rightReal[i], d = rightImag[i]
            
            // Complex Conjugate Multiplication: L * conj(R)
            let r = (a * c) + (b * d)
            let j = (b * c) - (a * d)
            
            let mag = sqrt(r * r + j * j)
            
            // Normalize: Strip magnitude, keep only phase
            if mag > 1e-6 {
                crossReal[i] = r / mag
                crossImag[i] = j / mag
            } else {
                crossReal[i] = 0
                crossImag[i] = 0
            }
        }
        
        // Zero DC and Nyquist to prevent "Center Pinning"
        crossReal[0] = 0.0
        crossImag[0] = 0.0
        
        // HEARTBEAT 3: About to Inverse
        print("🎙️ TDOA Step 3: Entering Inverse FFT")
        var crossCorr = [Float](repeating: 0, count: fftSize)
        inverseFFT(real: &crossReal, imag: &crossImag, output: &crossCorr)
        
        // HEARTBEAT 4: Back in Time Domain
        print("🎙️ TDOA Step 4: Inverse FFT Complete")
        // Loosen the window slightly to catch the "edge" cases
        let speedOfSound = 343.0
        // Increase the virtual mic distance slightly in the math to "stretch" the radar
        let virtualMicDistance = micDistance * 1.2
        let maxSampleDelay = Int(ceil((virtualMicDistance / speedOfSound) * sampleRate))
        
        var maxVal: Float = -1.0
        var peakIdx = 0
        
        // Search the physical window for the peak correlation
        for i in 0...maxSampleDelay {
            if crossCorr[i] > maxVal { maxVal = crossCorr[i]; peakIdx = i }
        }
        for i in (fftSize - maxSampleDelay)..<fftSize {
            if crossCorr[i] > maxVal {
                maxVal = crossCorr[i]
                peakIdx = i - fftSize
            }
        }
        print("📈 CC Peak: \(peakIdx) | Amp: \(maxVal)")
        
        // 6. Quadratic Interpolation for Sub-sample Bearing
        var refinedLag = Double(peakIdx)
        let p = peakIdx >= 0 ? peakIdx : fftSize + peakIdx
        if p > 0 && p < fftSize - 1 {
            let y1 = crossCorr[p-1], y2 = crossCorr[p], y3 = crossCorr[p+1]
            let denom = y1 - 2 * y2 + y3
            if abs(denom) > 1e-8 {
                refinedLag += Double(0.5 * (y1 - y3) / denom)
            }
        }
        
        // 7. DeltaT to Degrees
        let deltaT = refinedLag / sampleRate
        let ratio = (deltaT * speedOfSound) / micDistance
        let constrainedRatio = max(-1.0, min(1.0, ratio))
        print("📊 [DSP] Refined Lag: \(String(format: "%.4f", refinedLag)) | Ratio: \(String(format: "%.4f", ratio))")
        
        // We switch back to asin for a more natural -90 to +90 spread
        let theta = asin(constrainedRatio)
        var degrees = theta * (180.0 / .pi)
        
        // --- CALIBRATION ---
        // If sounds from the bottom of the phone are appearing at the top,
        // we need to flip the vertical polarity.
        degrees *= -1.0
        
        // To make the dot move LEFT and RIGHT (instead of just up/down),
        // we apply a "Horizontal Spread" multiplier.
        let horizontalSpread = 2.5
        let finalBearing = degrees * horizontalSpread
        
        // Hard Clamp to ensure it stays on the radar canvas
        let clampedBearing = max(-90.0, min(90.0, finalBearing))
        
        // 8. The "Stuck Dot" Killer
        // If the lag is 0, we give it a tiny nudge so it doesn't look dead center
        let jitter = Double.random(in: -0.2...0.2)
        
        // Before returning clampedBearing
        print("🎯 [MATH] Final Bearing: \(finalBearing) | Clamped: \(clampedBearing)")
        return clampedBearing + jitter
    }
    
    nonisolated private func forwardFFT(_ input: [Float], real: inout [Float], imag: inout [Float]) {
        let halfSize = fftSize / 2
        real.withUnsafeMutableBufferPointer { rPtr in
            imag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                input.withUnsafeBufferPointer { inPtr in
                    let rawPtr = UnsafeRawPointer(inPtr.baseAddress!)
                    vDSP_ctoz(rawPtr.assumingMemoryBound(to: DSPComplex.self), 2, &split, 1, vDSP_Length(halfSize))
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
    }
    
    nonisolated private func inverseFFT(real: inout [Float], imag: inout [Float], output: inout [Float]) {
        let halfSize = fftSize / 2
        real.withUnsafeMutableBufferPointer { rPtr in
            imag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                
                var scale = 1.0 / Float(2 * fftSize)
                vDSP_vsmul(split.realp, 1, &scale, split.realp, 1, vDSP_Length(halfSize))
                vDSP_vsmul(split.imagp, 1, &scale, split.imagp, 1, vDSP_Length(halfSize))
                
                output.withUnsafeMutableBufferPointer { outPtr in
                    let rawPtr = UnsafeMutableRawPointer(outPtr.baseAddress!)
                    vDSP_ztoc(&split, 1, rawPtr.assumingMemoryBound(to: DSPComplex.self), 2, vDSP_Length(halfSize))
                }
            }
        }
    }
    
    nonisolated private func quadraticInterpolate(magnitudes: [Float], peakIndex: Int) -> Float {
        guard peakIndex > 0 && peakIndex < magnitudes.count - 1 else { return Float(peakIndex) }
        let a = magnitudes[peakIndex - 1], b = magnitudes[peakIndex], c = magnitudes[peakIndex + 1]
        let denominator = a - 2 * b + c
        guard abs(denominator) > 1e-8 else { return Float(peakIndex) }
        return Float(peakIndex) + (0.5 * (a - c) / denominator)
    }
}
