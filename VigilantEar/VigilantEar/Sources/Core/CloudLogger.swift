import Foundation
import FirebaseFirestore

struct CloudLogger {
    static let shared = CloudLogger()
    
    // Grab a reference to the Google Cloud Database
    private let db = Firestore.firestore()
    
    func logEvent(_ event: SoundEvent) async {
        
        // THE BOUNCER: If it's not an emergency, silently drop it.
        guard event.isEmergency else { return }
        
        var eventData: [String: Any] = [
            "sessionID": event.id.uuidString, // Groups the whole drive-by together!
            "threatLabel": event.threatLabel,
            "bearing": event.bearing,
            "distance": event.distance,
            "energy": event.energy,
            "emergency": event.isEmergency,
            // THE FIX: Added the new Doppler approach boolean
            "isApproaching": event.isApproaching,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        // Safely unwrap and append the Optionals
        if let lat = event.latitude, let lon = event.longitude {
            eventData["latitude"] = lat
            eventData["longitude"] = lon
        }
        
        if let doppler = event.dopplerRate {
            eventData["dopplerRate"] = doppler
        }
        
        do {
            // THE FIX: Use `event.id` as the document ID so it creates a new row for every tick!
            try await db.collection(DependencyContainer.dataStoreName).document(event.id.uuidString).setData(eventData)
            //print("☁️ SUCCESS: Threat logged to Google Cloud!")
        } catch {
            print("⚠️ Cloud write queued (Offline): \(error.localizedDescription)")
        }
    }
}
