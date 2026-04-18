//
//  SirenDopplerTracker.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/13/26.
//


import Foundation

nonisolated struct SirenDopplerTracker: Sendable {
    private var frequencyBuffer: [Double] = []
    private let maxBufferSize = 40 // roughly 2 seconds of audio frames
    private var baselineCenter: Double?
    
    mutating func update(with frequency: Double, confidence: Float) -> (isApproaching: Bool, shiftHz: Double)? {
        // Ignore muddy/unconfident FFT results
        guard confidence > 0.3 else { return nil } 
        
        frequencyBuffer.append(frequency)
        if frequencyBuffer.count > maxBufferSize {
            frequencyBuffer.removeFirst()
        }
        
        // We need at least half a second of continuous data to find the top and bottom of the siren's wail
        guard frequencyBuffer.count > 10 else { return nil }
        
        guard let minFreq = frequencyBuffer.min(), let maxFreq = frequencyBuffer.max() else { return nil }
        
        // Calculate the exact mathematical center of the current wail
        let currentCenter = (maxFreq + minFreq) / 2.0
        
        if baselineCenter == nil {
            baselineCenter = currentCenter
            return nil
        }
        
        // Slowly adapt the baseline (Exponential Moving Average) so it doesn't jump wildly
        baselineCenter = (baselineCenter! * 0.95) + (currentCenter * 0.05)
        
        let shift = currentCenter - baselineCenter!
        
        // If the center point has shifted physically upward by more than 5 Hz, it is approaching
        let isApproaching = shift > 5.0
        
        return (isApproaching, shift)
    }
}
