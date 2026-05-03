//
//  PerformanceLogger.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/7/26.
//

import Foundation
import os.signpost
import os.log
@unsafe @preconcurrency import FirebaseFirestore

/// A thread-safe logger for tracking performance metrics and execution time.
/// Supports both modern OSSignpost intervals and legacy string logging.
public final class PerformanceLogger: @unchecked Sendable {
    
    // A single shared instance for easy access across the app
    public static let shared = PerformanceLogger()
    
    // A thread-safe dictionary to keep track of active signpost IDs for tasks
    private var activeSignposts: [String: OSSignpostID] = [:]
    
    // A lock to prevent race conditions when accessing the dictionary
    private let lock = NSLock()
    
    // THE FIX: Add database reference and a unique ID for this app launch
    private let db = Firestore.firestore()
    private let sessionLaunchID = UUID().uuidString
    
    // MARK: - Modern Signpost Tracking
    
    public func start(task: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Generate a unique ID for this specific execution of the task
        let signpostID = OSSignpostID(log: AppGlobals.performanceLog)
        activeSignposts[task] = signpostID
        
        // Begin the signpost interval
        unsafe os_signpost(.begin, log: AppGlobals.performanceLog, name: "TaskExecution", signpostID: signpostID, "Start: %{public}@", task)
    }
    
    /// Stops a performance tracking interval and logs the duration.
    /// - Parameter task: The unique string identifying the task, matching the one used in `start(task:)`.
    public func stop(task: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Retrieve the ID associated with the task
        guard let signpostID = activeSignposts[task] else {
            unsafe os_log("PerformanceLogger: Attempted to stop a task that wasn't started: %{public}@", log: AppGlobals.standardLog, type: .error, task)
            return
        }
        
        // End the signpost interval
        unsafe os_signpost(.end, log: AppGlobals.performanceLog, name: "TaskExecution", signpostID: signpostID, "Stop: %{public}@", task)
        
        // Remove the task from active tracking
        activeSignposts.removeValue(forKey: task)
    }
    
    // MARK: - Remote Telemetry
    public func fireStoreTelemetry(step: String, message: String, firestoreCollectionName: String, isError: Bool = false) {

        unsafe os_log("%{public}@ %{public}@", log: AppGlobals.standardLog, type: (isError ? .error : .debug), (isError ? "❌" : "🐞"), message)
        
        if (AppGlobals.exceptionsDataStoreName != firestoreCollectionName) {
            guard AppGlobals.logToCloud else { return }
        }
        
        // 2. Beam to Firebase
        let logData: [String: Any] = [
            "sessionID": sessionLaunchID,
            "timestamp": FieldValue.serverTimestamp(),
            "step": step,
            "message": message,
            "isError": isError
        ]
        
        Task.detached(priority: .background) {
            do {
                try await self.db.collection(firestoreCollectionName).addDocument(data: logData)
            } catch {
                unsafe os_log("%{public}@ %{public}@ Error: %{public}@", log: AppGlobals.standardLog, type: .error, "⚠️ Telemetry failed to send to:", firestoreCollectionName, error.localizedDescription)
            }
        }
        
    }
    
}
