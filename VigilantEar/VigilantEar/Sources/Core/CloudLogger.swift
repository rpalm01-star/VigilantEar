import Foundation
import FirebaseFirestore

// THE FIX: Upgraded to an 'actor' to safely handle high-speed concurrent data from the pipeline
actor CloudLogger {
    
    static let shared = CloudLogger()
    
    private let db = Firestore.firestore()
    
    // Memory bank to cache the most recent frame of an active vehicle
    private var activeSessions: [UUID: (lastEvent: SoundEvent, lastSeen: Date)] = [:]
    private var isCleanupRunning = false
    
    func logEvent(_ event: SoundEvent) async {
        guard AppGlobals.logToCloud else { return }
        
        let now = Date()
        let sessionID = event.sessionID
        
        // 1. IS IT A BRAND NEW VEHICLE?
        if activeSessions[sessionID] == nil {
            await writeToCloud(event: event, status: "FIRST_CONTACT")
        }
        
        // 2. OVERWRITE THE LOCAL CACHE WITH THE NEWEST FRAME
        activeSessions[sessionID] = (lastEvent: event, lastSeen: now)
        
        // 3. START THE "LAST CONTACT" MONITOR IF NEEDED
        if !isCleanupRunning {
            startCleanupLoop()
        }
    }
    
    // --- THE NEW AUTOPURGE FUNCTION ---
    /// Fetches and deletes every document in the target collection.
    /// WARNING: Use for development/debugging only.
    func purgeOldLogs() async {
        
        if (!AppGlobals.purgeCloudLogsOnStartup) {
            let msg = "✨ Firestore '\(AppGlobals.logDataStoreName)' purge is disabled because AppGlobals.purgeCloudLogsOnStartup is true."
            AppGlobals.doLog(message: msg, step: "CLOUDLOGGER")
            return
        }
        
        let logsCollection = db.collection(AppGlobals.logDataStoreName)
        
        do {
            // 1. Fetch all existing log documents
            let snapshot = try await logsCollection.getDocuments()
            
            guard !snapshot.documents.isEmpty else {
                let msg = "✨ Firestore '\(AppGlobals.logDataStoreName)' collection is already empty."
                AppGlobals.doLog(message: msg, step: "CLOUDLOGGER")
                return
            }
            
            // 2. Create a batch to delete them all at once
            let batch = db.batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            // 3. Commit the batch
            try await batch.commit()
            
            let msg = "🗑️ Successfully purged \(snapshot.documents.count) old logs from Firestore."
            AppGlobals.doLog(message: msg, step: "CLOUDLOGGER")
            
        } catch {
            let msg = "⚠️ Failed to purge old logs: \(error.localizedDescription)"
            AppGlobals.doLog(message: msg, step: "CLOUDLOGGER")
        }
    }
    
    // A self-managing background loop that watches for faded sirens
    private func startCleanupLoop() {
        isCleanupRunning = true
        
        Task {
            while !activeSessions.isEmpty {
                // Check the cache every 2 seconds
                try? await Task.sleep(for: .seconds(2))
                let now = Date()
                
                for (sessionID, data) in activeSessions {
                    // If we haven't heard this specific siren in 2 seconds, it drove away!
                    if now.timeIntervalSince(data.lastSeen) > 2.0 {
                        
                        // THIS WAS THE LAST FRAME!
                        await writeToCloud(event: data.lastEvent, status: "LAST_CONTACT")
                        
                        // Remove it from memory
                        activeSessions.removeValue(forKey: sessionID)
                    }
                }
            }
            // Once the street is quiet and the cache is empty, shut down the loop
            isCleanupRunning = false
        }
    }
    
    private func writeToCloud(event: SoundEvent, status: String) async {
        var eventData: [String: Any] = [
            "sessionID": event.sessionID.uuidString,
            "threatLabel": event.threatLabel,
            "realThreatLabel": event.realThreatLabel,
            "bearing": event.bearing,
            "distance": event.distance,
            "energy": event.energy,
            "emergency": await event.isEmergency,
            "isApproaching": event.isApproaching,
            "contactPhase": status, // THE FIX: Flags it as FIRST_CONTACT or LAST_CONTACT
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        if let lat = event.latitude, let lon = event.longitude {
            eventData["latitude"] = lat
            eventData["longitude"] = lon
        }
        
        if let doppler = event.dopplerRate {
            eventData["dopplerRate"] = doppler
        }
        
        do {
            try await db.collection(AppGlobals.dataStoreName).document(event.id.uuidString).setData(eventData)
        } catch {
            let msg = "⚠️ Cloud write queued (Offline): \(error.localizedDescription)"
            AppGlobals.doLog(message: msg, step: "CLOUDLOGGER")
        }
    }
}
