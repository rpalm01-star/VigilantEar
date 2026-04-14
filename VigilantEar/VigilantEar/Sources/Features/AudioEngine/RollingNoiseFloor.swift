//
//  RollingNoiseFloor.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/13/26.
//


import Foundation

/// A high-performance, fixed-size ring buffer to track the rolling noise floor.
struct RollingNoiseFloor: Sendable {
    private var buffer: [Float]
    private var index = 0
    private var isFull = false
    
    init(windowSize: Int) {
        self.buffer = [Float](repeating: 0.0, count: windowSize)
    }
    
    mutating func append(_ dbLevel: Float) {
        buffer[index] = dbLevel
        index += 1
        if index >= buffer.count {
            index = 0
            isFull = true
        }
    }
    
    var currentBaselineDB: Float? {
        guard index > 0 || isFull else { return nil }
        let activeElements = isFull ? buffer.count : index
        // Prevent calculating an average across 0.0 initialized elements
        let sum = buffer[0..<activeElements].reduce(0, +)
        return sum / Float(activeElements)
    }
}
