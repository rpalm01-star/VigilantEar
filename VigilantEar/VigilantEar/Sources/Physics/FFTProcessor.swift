//
//  FFTProcessor.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/13/26.
//  Reviewed and refined by Grok on 5/2/2026
//

import Foundation
import Accelerate

/// High-performance FFT processor using Apple's Accelerate framework.
///
/// This class handles:
/// - Single dominant frequency analysis
/// - Multi-target peak detection (up to N simultaneous sounds)
/// - GCC-PHAT Time Difference of Arrival (TDOA) for bearing estimation
/// - Quadratic interpolation for sub-bin frequency accuracy
///
/// It is the core DSP engine behind all real-time acoustic detection.
final class FFTProcessor: @unchecked Sendable {
    
    // MARK: - Configuration
    
    private let fftSize: Int
    private let log2n: vDSP_Length
    nonisolated(unsafe) private let fftSetup: FFTSetup
    private let window: [Float]
    
    // MARK: - Initialization
    
    nonisolated init(fftSize: Int) {
        precondition(fftSize > 0 && (fftSize & (fftSize - 1)) == 0,
                     "FFT size must be a power of 2")
        
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(self.log2n, FFTRadix(kFFTRadix2))!
        
        // Pre-compute Hann window for better frequency resolution
        self.window = {
            var w = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&w, vDSP_Length(fftSize), 0)
            return w
        }()
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    // MARK: - Single Target Analysis
    
    /// Analyzes a single audio buffer and returns the dominant frequency + confidence.
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
    
    // MARK: - Multi-Target Analysis
    
    /// Finds up to `maxPeaks` independent frequency peaks in the audio buffer.
    nonisolated func analyzeMultiple(samples: [Float], sampleRate: Double, maxPeaks: Int = 3) -> [(frequency: Double, confidence: Float)] {
        guard samples.count == fftSize else { return [] }
        
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
        
        let sum = magnitudes.reduce(0, +)
        let avg = sum / Float(halfSize)
        let threshold = avg * 2.5
        
        var peaks: [(index: Int, mag: Float)] = []
        
        for i in 1..<(halfSize - 1) {
            let m = magnitudes[i]
            if m > threshold && m > magnitudes[i-1] && m > magnitudes[i+1] {
                peaks.append((index: i, mag: m))
            }
        }
        
        peaks.sort { $0.mag > $1.mag }
        let topTargets = peaks.prefix(maxPeaks)
        
        return topTargets.map { peak in
            let refinedIndex = quadraticInterpolate(magnitudes: magnitudes, peakIndex: peak.index)
            let freq = Double(refinedIndex) * (sampleRate / Double(fftSize))
            let conf = min(peak.mag / avg, 1.0)
            return (freq, conf)
        }
    }
    
    // MARK: - TDOA Bearing Estimation (GCC-PHAT)
    
    /// Calculates bearing using GCC-PHAT Time Difference of Arrival.
    nonisolated func calculateTDOA(left: [Float], right: [Float], sampleRate: Double, micDistance: Double = 0.15) -> Double? {
        let safeLeft = Array(left.prefix(fftSize))
        let safeRight = Array(right.prefix(fftSize))
        
        guard safeLeft.count == fftSize, safeRight.count == fftSize else { return nil }
        
        let halfSize = fftSize / 2
        var leftReal = [Float](repeating: 0, count: halfSize)
        var leftImag = [Float](repeating: 0, count: halfSize)
        var rightReal = [Float](repeating: 0, count: halfSize)
        var rightImag = [Float](repeating: 0, count: halfSize)
        
        forwardFFT(safeLeft, real: &leftReal, imag: &leftImag)
        forwardFFT(safeRight, real: &rightReal, imag: &rightImag)
        
        var crossReal = [Float](repeating: 0, count: halfSize)
        var crossImag = [Float](repeating: 0, count: halfSize)
        
        // Frequency-domain low-pass filter (removes high-frequency noise)
        let cutoffFrequency: Double = 1200.0
        let maxBin = Int((cutoffFrequency / sampleRate) * Double(fftSize))
        
        for i in 0..<halfSize {
            if i > maxBin {
                crossReal[i] = 0.0
                crossImag[i] = 0.0
                continue
            }
            
            let a = leftReal[i], b = leftImag[i]
            let c = rightReal[i], d = rightImag[i]
            let r = (a * c) + (b * d)
            let j = (b * c) - (a * d)
            let mag = sqrt(r * r + j * j)
            
            if mag > 1e-6 {
                crossReal[i] = r / mag
                crossImag[i] = j / mag
            }
        }
        
        crossReal[0] = 0.0
        crossImag[0] = 0.0
        
        var crossCorr = [Float](repeating: 0, count: fftSize)
        inverseFFT(real: &crossReal, imag: &crossImag, output: &crossCorr)
        
        let speedOfSound = 343.0
        let virtualMicDistance = micDistance * 1.2
        let maxSampleDelay = Int(ceil((virtualMicDistance / speedOfSound) * sampleRate))
        
        // Find highest peak within physical constraints
        var maxVal: Float = -1.0
        var absolutePeakIndex = 0
        var logicalLagIndex = 0
        
        for i in 0...maxSampleDelay {
            if crossCorr[i] > maxVal {
                maxVal = crossCorr[i]
                absolutePeakIndex = i
                logicalLagIndex = i
            }
        }
        for i in (fftSize - maxSampleDelay)..<fftSize {
            if crossCorr[i] > maxVal {
                maxVal = crossCorr[i]
                absolutePeakIndex = i
                logicalLagIndex = i - fftSize
            }
        }
        
        let fractionalPeak = quadraticInterpolate(magnitudes: crossCorr, peakIndex: absolutePeakIndex)
        let offset = Double(fractionalPeak) - Double(absolutePeakIndex)
        let refinedLag = Double(logicalLagIndex) + offset
        
        let deltaT = refinedLag / sampleRate
        let ratio = (deltaT * speedOfSound) / micDistance
        let constrainedRatio = max(-1.0, min(1.0, ratio))
        let theta = asin(constrainedRatio)
        
        var degrees = theta * (180.0 / .pi)
        degrees *= -1.0
        
        let horizontalSpread = 2.5
        let finalBearing = degrees * horizontalSpread
        let clampedBearing = max(-90.0, min(90.0, finalBearing))
        let jitter = Double.random(in: -0.2...0.2)
        
        return clampedBearing + jitter
    }
    
    // MARK: - Private FFT Helpers
    
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
