//
//  PerformanceLogger.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/7/26.
//

import Foundation
import FirebaseFirestore
import os.log

public final class PerformanceLogger: @unchecked Sendable {
    
    // A single shared instance for easy access across the app
    public static let shared = PerformanceLogger()

    private let logger = Logger(subsystem: "com.vigilantear.app", category: "Performance")

    // MARK: - Remote Telemetry
    public func fireStoreTelemetry(step: String, message: String, firestoreCollectionName: String, isError: Bool = false) {
        
        let logData: [String: Any] = [
            "sessionID": AppGlobals.sessionID.uuidString,
            "timestamp": FieldValue.serverTimestamp(),
            "step": step,
            "message": message,
            "isError": isError,
            "expireAt": Timestamp(date: Date().addingTimeInterval(12 * 60 * 60))
        ]

        Task.detached(priority: .background) {
            self.logger.debug("\(step): \(message)")
        }
        
        if (AppGlobals.exceptionsDataStoreName != firestoreCollectionName) {
            guard AppGlobals.logToCloud else { return }
        }
        
        Task.detached(priority: .background) {
            do {
                try await DependencyContainer.shared.db.collection(firestoreCollectionName).addDocument(data: logData)
            } catch {
                // No action
            }
        }
        
    }
    
}
