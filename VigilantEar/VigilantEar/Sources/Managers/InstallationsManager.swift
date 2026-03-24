import Foundation
import UIKit
import FirebaseFirestore

class InstallationsManager {
    
    static let shared = InstallationsManager()
    
    func executeFirstRunTelemetryIfNeeded() {
        
        let firstRunKey = "hasLoggedInstallationTelemetry(\(AppGlobals.appVersion))"
        if (!AppGlobals.isDebugDevice) {
            guard !UserDefaults.standard.bool(forKey: firstRunKey) else { return }
        }
        
        // Use a Task with a tiny sleep to ensure the UI has hydrated
        Task { @MainActor in
            let telemetryData: [String: Any] = [
                "appVersion": AppGlobals.appVersion,
                "osVersion": UIDevice.current.systemVersion,
                "systemName": UIDevice.current.systemName,
                "installedAt": FieldValue.serverTimestamp()
            ]
            Task.detached(priority: .background) {
                await DependencyContainer.shared.db.collection(AppGlobals.installationsDataStoreName).addDocument(data: telemetryData) { error in
                    if error == nil {
                        UserDefaults.standard.set(true, forKey: firstRunKey)
                    }
                }
            }
        }
    }
}
