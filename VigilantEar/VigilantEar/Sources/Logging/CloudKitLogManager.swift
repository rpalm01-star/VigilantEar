import Foundation
import CloudKit
import UIKit
import os.log

class CloudKitLogManager {
    
    // 👇 Switch to the PUBLIC database so you can actually read the logs
    private static let database = CKContainer(identifier: "iCloud.com.rpalm01-star.VigilantEar").publicCloudDatabase
    private static var hasPurgeRun : Bool = false
    
    // Define your tables (Schema-on-Write will create these automatically)
    private enum Table: String {
        case installations = "Installations"
        case exceptions = "Exceptions"
        case logs = "Logs"
    }
    
    private static let logger = {
        let logger = Logger(subsystem: "com.vigilantear.app", category: "General")
        return logger
    }
    
    public static func purgeLogTable(in tableName: String = Table.logs.rawValue) {
        guard !hasPurgeRun else { return }
        hasPurgeRun = true
        
        Task.detached(priority: .background) {
            // 1. Only query records where the expiration date has passed
            let predicate = NSPredicate(format: "expireAt < %@", NSDate())
            let query = CKQuery(recordType: tableName, predicate: predicate)
            
            do {
                // 2. Initial fetch
                var (matchResults, cursor) = try await database.records(matching: query, desiredKeys: ["recordID"])
                
                var done = false
                var doCount = 0
                let doCountMax = 3
                
                while !done {
                    
                    doCount += 1
                    if (doCount > doCountMax) {
                        await logger().debug("✅ Table \(tableName) purge loops exceeded \(doCount-1). Stopping.")
                        done = true
                        break
                    }
                    
                    let recordIDs = matchResults.compactMap { (id, _) in return id }
                    
                    guard !recordIDs.isEmpty else {
                        await logger().debug("✅ Table \(tableName) found no expired rows to purge.")
                        done = true
                        break
                    }
                    
                    // Delete the current batch of IDs
                    let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordIDs)
                    await logger().debug("✅ Successfully deleted \(deleteResults.count) expired records from \(tableName).")
                    
                    // 3. If CloudKit provided a cursor, there are more pages to fetch and delete
                    if let nextCursor = cursor {
                        let nextBatch = try await database.records(continuingMatchFrom: nextCursor)
                        matchResults = nextBatch.matchResults
                        cursor = nextBatch.queryCursor
                    } else {
                        // No cursor means we have reached the end of the expired records
                        done = true
                    }
                }
            } catch {
                await logger().error("❌ Failed to purge records from \(tableName): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Remote Logging
    public static func log(step: String, message: String, isError: Bool = false) {
        Task.detached(priority: .background) {
            let expireIncrement : TimeInterval = 12 * 60 * 60
            let record = CKRecord(recordType: Table.logs.rawValue)
            record["appTitle"] = AppGlobals.appTitle.key
            record["appVersion"] = AppGlobals.appVersion
            record["sessionID"] = AppGlobals.sessionID.uuidString
            record["step"] = step
            record["message"] = message
            record["isError"] = isError
            record["expireAt"] = Date().addingTimeInterval(expireIncrement)
            await logger().debug("\(record)")
            guard AppGlobals.logToCloud else { return }
            let _ = try? await self.database.save(record)
        }
    }
    
    public static func logInstallation() {
        Task.detached(priority: .background) {
            let firstRunKey = "hasLoggedInstallationTelemetry(\(AppGlobals.appVersion))"
            if !AppGlobals.isDebugDevice {
                guard !UserDefaults.standard.bool(forKey: firstRunKey) else { return }
            } else {
                await purgeLogTable()
            }
            UserDefaults.standard.set(true, forKey: firstRunKey)
            let record = CKRecord(recordType: Table.installations.rawValue)
            record["appTitle"] = AppGlobals.appTitle.key
            record["appVersion"] = AppGlobals.appVersion
            record["sessionId"] = AppGlobals.sessionID.uuidString
            record["osVersion"] = await UIDevice.current.systemVersion
            record["systemName"] = await UIDevice.current.systemName
            await logger().debug("\(record)")
            let _ = try? await self.database.save(record)
        }
    }
    
    public static func logException(description: String) {
        Task.detached(priority: .background) {
            let record = CKRecord(recordType: Table.exceptions.rawValue)
            record["appTitle"] = AppGlobals.appTitle.key
            record["appVersion"] = AppGlobals.appVersion
            record["sessionId"] = AppGlobals.sessionID.uuidString
            record["description"] = description
            await logger().debug("\(record)")
            let _ = try? await self.database.save(record)
        }
    }
    
}
