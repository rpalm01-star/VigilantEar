//
//  CloudLogger.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/15/26.
//

import Foundation
import FirebaseFirestore

struct CloudLogger {
    static let shared = CloudLogger()
    
    // Grab a reference to the Google Cloud Database
    private let db = Firestore.firestore()
    
    // 1. THE FIX: Mark the function as 'async' so it matches the caller!
    func logEvent(_ event: SoundEvent) async {
        
        // THE BOUNCER: If it's not an emergency, silently drop it.
        guard event.isEmergency else { return }
        
        var eventData: [String: Any] = [
            // 2. THE FIX: Save the Session ID in the database so the row knows what it belongs to!
            "sessionID": event.sessionID.uuidString,
            "threatLabel": event.threatLabel,
            "bearing": event.bearing,
            "distance": event.distance,
            "energy": event.energy,
            "emergency": event.isEmergency,
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
        
        // 3. THE FIX: Use modern Swift async/await instead of the messy closure
        do {
            try await db.collection("detected_threats").document(event.sessionID.uuidString).setData(eventData)
            //print("☁️ SUCCESS: Threat logged to Google Cloud!")
        } catch {
            print("⚠️ Cloud write queued (Offline): \(error.localizedDescription)")
        }
    }
}
