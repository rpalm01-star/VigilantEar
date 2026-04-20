//
//  PerformanceLogger.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/7/26.
//

import Foundation
import os.signpost
import os.log
import FirebaseFirestore

/// A thread-safe logger for tracking performance metrics and execution time.
/// Supports both modern OSSignpost intervals and legacy string logging.
public final class PerformanceLogger: @unchecked Sendable {
    
    // A single shared instance for easy access across the app
    public static let shared = PerformanceLogger()
    
    // Modern signpost logger
    private let performanceLog: OSLog
    
    // Legacy standard logger (maintains backwards compatibility)
    private let standardLog: OSLog
    
    // A thread-safe dictionary to keep track of active signpost IDs for tasks
    private var activeSignposts: [String: OSSignpostID] = [:]
    
    // A lock to prevent race conditions when accessing the dictionary
    private let lock = NSLock()
    
    // THE FIX: Add database reference and a unique ID for this app launch
    private let db = Firestore.firestore()
    private let sessionLaunchID = UUID().uuidString
    
    
    // Private initializer to enforce the singleton pattern
    private init() {
        self.performanceLog = OSLog(subsystem: "com.VigilantEar.app", category: "Performance")
        self.standardLog = OSLog(subsystem: "com.VigilantEar.app", category: "General")
    }
    
    // MARK: - Modern Signpost Tracking
    
    public func start(task: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Generate a unique ID for this specific execution of the task
        let signpostID = OSSignpostID(log: performanceLog)
        activeSignposts[task] = signpostID
        
        // Begin the signpost interval
        os_signpost(.begin, log: performanceLog, name: "TaskExecution", signpostID: signpostID, "Start: %{public}@", task)
    }
    
    /// Stops a performance tracking interval and logs the duration.
    /// - Parameter task: The unique string identifying the task, matching the one used in `start(task:)`.
    public func stop(task: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Retrieve the ID associated with the task
        guard let signpostID = activeSignposts[task] else {
            os_log("PerformanceLogger: Attempted to stop a task that wasn't started: %{public}@", log: standardLog, type: .error, task)
            return
        }
        
        // End the signpost interval
        os_signpost(.end, log: performanceLog, name: "TaskExecution", signpostID: signpostID, "Stop: %{public}@", task)
        
        // Remove the task from active tracking
        activeSignposts.removeValue(forKey: task)
    }
    
    // MARK: - Remote Telemetry
    
    /// Beams a debug log to Firebase so you can read it after a field test
    public func logTelemetry(step: String, message: String, isError: Bool = false) {
        let icon = isError ? "❌" : "🐞"
        print("\(icon) [\(step)] \(message)")
        
        // 2. Beam to Firebase
        let logData: [String: Any] = [
            "sessionID": sessionLaunchID,
            "timestamp": FieldValue.serverTimestamp(),
            "step": step,
            "message": message,
            "isError": isError
        ]
        
        if (AppGlobals.logToCloud) {
            Task.detached(priority: .background) {
                do {
                    try await self.db.collection(AppGlobals.logDataStoreName).addDocument(data: logData)
                } catch {
                    print("⚠️ Telemetry failed to send: \(error.localizedDescription)")
                }
            }
            
        }
    }
}
