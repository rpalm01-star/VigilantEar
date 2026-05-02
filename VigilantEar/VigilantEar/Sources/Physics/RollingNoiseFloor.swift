//
//  RollingNoiseFloor.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/13/26.
//  Reviewed and refined by Grok on 5/2/2026
//

import Foundation

/// A high-performance fixed-size ring buffer that tracks the rolling noise floor
/// in decibels (dB).
///
/// This is used by the audio pipeline to establish a dynamic baseline for what
/// constitutes "real" sound versus background noise. It automatically discards
/// old values as new ones arrive.
struct RollingNoiseFloor: Sendable {
    
    // MARK: - Configuration
    
    /// Number of recent samples to keep in the rolling window
    private let windowSize: Int
    
    // MARK: - Private State
    
    /// Circular buffer holding the most recent dB levels
    private var buffer: [Float]
    
    /// Current write position in the circular buffer
    private var index = 0
    
    /// Whether we have filled the buffer at least once
    private var isFull = false
    
    // MARK: - Initialization
    
    /// Creates a new rolling noise floor tracker.
    ///
    /// - Parameter windowSize: How many recent audio frames to average.
    ///                         Larger values = smoother but slower response.
    init(windowSize: Int) {
        self.windowSize = windowSize
        self.buffer = [Float](repeating: 0.0, count: windowSize)
    }
    
    // MARK: - Public API
    
    /// Adds a new dB level to the rolling window.
    ///
    /// When the buffer is full, the oldest value is automatically overwritten.
    mutating func append(_ dbLevel: Float) {
        buffer[index] = dbLevel
        index += 1
        
        if index >= windowSize {
            index = 0
            isFull = true
        }
    }
    
    /// Returns the current average noise floor in dB, or `nil` if we don't have
    /// enough data yet.
    var currentBaselineDB: Float? {
        guard index > 0 || isFull else { return nil }
        
        let activeCount = isFull ? windowSize : index
        
        // Only average the elements that actually contain real data
        let sum = buffer[0..<activeCount].reduce(0, +)
        return sum / Float(activeCount)
    }
    
    /// Resets the rolling buffer to empty (useful when audio session restarts
    /// or after long periods of silence).
    mutating func reset() {
        buffer = [Float](repeating: 0.0, count: windowSize)
        index = 0
        isFull = false
    }
}
