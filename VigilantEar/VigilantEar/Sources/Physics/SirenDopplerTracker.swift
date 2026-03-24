//
//  SirenDopplerTracker.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/13/26.
//  Reviewed and refined by Grok on 5/2/2026
//

import Foundation

/// Tracks the Doppler shift of tonal sounds (primarily sirens) over time.
///
/// This struct maintains a rolling buffer of frequency peaks and compares the
/// current center frequency against a slowly adapting baseline. It returns
/// whether the sound source appears to be **approaching** (rising pitch) and
/// the frequency shift in Hz.
nonisolated struct SirenDopplerTracker: Sendable {
    
    // MARK: - Configuration
    
    private let maxBufferSize = 40          // ≈ 2 seconds of data
    private let minSamplesForDecision = 12  // Need decent history before deciding
    
    // Hysteresis prevents rapid flipping between approaching/receding
    private let approachThreshold = 5.0     // Hz positive shift = approaching
    private let recedeThreshold = -4.0      // Hz negative shift = receding
    
    // MARK: - Private State
    
    private var frequencyBuffer: [Double] = []
    private var baselineCenter: Double? = nil
    private var lastUpdateTime: Date = .distantPast
    
    // MARK: - Public API
    
    /// Updates the tracker with a new frequency peak.
    ///
    /// - Parameters:
    ///   - frequency: Dominant frequency detected in this frame (Hz)
    ///   - confidence: Confidence score from the FFT peak detector (0.0–1.0)
    /// - Returns: Doppler information `(isApproaching, shiftHz)` if we have
    ///            enough stable data, otherwise `nil`.
    mutating func update(with frequency: Double, confidence: Float) -> (isApproaching: Bool, shiftHz: Double)? {
        
        // Ignore low-confidence readings
        guard confidence > 0.28 else { return nil }
        
        let now = Date()
        frequencyBuffer.append(frequency)
        
        if frequencyBuffer.count > maxBufferSize {
            frequencyBuffer.removeFirst()
        }
        
        // Need enough samples before making a reliable decision
        guard frequencyBuffer.count >= minSamplesForDecision else { return nil }
        
        guard let minFreq = frequencyBuffer.min(),
              let maxFreq = frequencyBuffer.max() else { return nil }
        
        let currentCenter = (maxFreq + minFreq) / 2.0
        
        // Initialize baseline on first valid reading
        if baselineCenter == nil {
            baselineCenter = currentCenter
            lastUpdateTime = now
            return nil
        }
        
        // Slowly adapt baseline using confidence-weighted EMA
        let weight = Double(confidence) * 0.08
        baselineCenter = (baselineCenter! * (1.0 - weight)) + (currentCenter * weight)
        
        let shiftHz = currentCenter - baselineCenter!
        
        // Apply hysteresis to avoid jitter
        let isApproaching: Bool
        if shiftHz > approachThreshold {
            isApproaching = true
        } else if shiftHz < recedeThreshold {
            isApproaching = false
        } else {
            // Stay in previous state if within hysteresis band
            return nil // or keep last known state if you prefer
        }
        
        lastUpdateTime = now
        return (isApproaching, shiftHz)
    }
    
    /// Resets the tracker (useful when switching targets or after long silence)
    mutating func reset() {
        frequencyBuffer.removeAll()
        baselineCenter = nil
    }
}
