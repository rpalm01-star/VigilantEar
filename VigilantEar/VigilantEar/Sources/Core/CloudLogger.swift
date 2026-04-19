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
        guard event.isEmergency else { return }
        
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
            "bearing": event.bearing,
            "distance": event.distance,
            "energy": event.energy,
            "emergency": event.isEmergency,
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
            try await db.collection(DependencyContainer.dataStoreName).document(event.id.uuidString).setData(eventData)
        } catch {
            print("⚠️ Cloud write queued (Offline): \(error.localizedDescription)")
        }
    }
}
