//
//  File.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/4/26.
//

import Foundation
import SwiftUI

struct PerformanceLogger {
    static func log(
        label: String = "M4",
        startTime: ContinuousClock.Instant,
        instance: Any, // Pass 'self' here
        function: String = #function // Automatically captures the method name
    ) {
        let clock = ContinuousClock()
        let elapsed = startTime.duration(to: clock.now)
        let timestamp = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3)))
        
        // Dynamically get the class name from the instance
        let className = String(describing: type(of: instance))
        
        print("[\(timestamp)] 🏎️ \(className).\(function) - \(label): \(elapsed.formatted(.units(allowed: [.milliseconds], width: .abbreviated)))")
    }
}
