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
    
    func logEvent(_ event: SoundEvent) {
        // THE BOUNCER: If it's not an emergency, silently drop it and cancel the cloud write.
        guard event.isEmergency else { return }
        
        var eventData: [String: Any] = [
            "id": event.id.uuidString,
            "threatLabel": event.threatLabel,
            "bearing": event.bearing,
            "distance": event.distance,
            "energy": event.energy,
            "emergency": event.isEmergency,
            // Firestorm trick: Use Google's atomic server time, not the iPhone's local clock!
            "timestamp": FieldValue.serverTimestamp() 
        ]
        
        // 2. Safely unwrap and append the Optionals
        if let lat = event.latitude, let lon = event.longitude {
            eventData["latitude"] = lat
            eventData["longitude"] = lon
        }
        
        if let doppler = event.dopplerRate {
            eventData["dopplerRate"] = doppler
        }
        
        // 2. Teleport it to the cloud.
        // If the phone is offline, Firebase silently caches this and sends it later.
        db.collection("detected_threats").document(event.id.uuidString).setData(eventData) { error in
            if let error = error {
                print("⚠️ Cloud write queued (Offline): \(error.localizedDescription)")
            } else {
                print("☁️ SUCCESS: Threat logged to Google Cloud!")
            }
        }
    }
}
