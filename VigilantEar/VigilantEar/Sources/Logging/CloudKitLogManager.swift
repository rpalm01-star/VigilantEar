import Foundation
import CloudKit
import UIKit
import os.log

class CloudKitLogManager {
    
    // 👇 Switch to the PUBLIC database so you can actually read the logs
    private static let database = CKContainer(identifier: "iCloud.com.rpalm01-star.VigilantEar").publicCloudDatabase
    private static var isEmptied : Bool = false
    
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
    
    public static func deleteAllRecords(in tableName: String = Table.logs.rawValue) {
        guard !isEmptied else { return }
        isEmptied = true
        Task.detached(priority: .background) {
            var done = false
            while !done {
                let query = CKQuery(recordType: tableName, predicate: NSPredicate(value: true))
                do {
                    let (matchResults, _) = try await database.records(matching: query, desiredKeys: ["recordID"])
                    let recordIDs = matchResults.compactMap { (id, result) in
                        return id
                    }
                    guard !recordIDs.isEmpty else {
                        await logger().debug("✅ Table \(tableName) is already empty.")
                        done = true
                        return
                    }
                    let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: recordIDs)
                    await logger().debug("✅ Successfully deleted \(deleteResults.count) records from \(tableName).")
                } catch {
                    await logger().error("❌ Failed to delete records from \(tableName): \(error.localizedDescription)")
                    done = true
                }
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
                await deleteAllRecords()
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
