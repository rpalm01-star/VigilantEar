import Foundation
import SwiftUI
import CoreLocation

struct SoundEvent: Identifiable {
    // 1. For the UI: Automatically generates a brand new, unique ID every tick so MapKit draws a trail.
    let id: UUID
    
    // 2. For the Cloud: The shared ID that groups this entire drive-by together.
    let sessionID: UUID
    
    var timestamp: Date
    var threatLabel: String
    var hitCount: Int = 1
    
    // ML Certainty (0.0 to 1.0)
    public let confidence: Double
    
    public var isEmergency: Bool {
        return SoundProfile.classify(threatLabel).isEmergency
    }
    
    public var isVehicle: Bool {
        return SoundProfile.classify(threatLabel).isVehicle
    }
    
    public var dotColor: Color {
        if (SoundProfile.classify(threatLabel).isEmergency) {return Color.red} else {return Color.cyan}
    }
    
    // MARK: - Spatial Data
    public let bearing: Double
    public let distance: Double
    public var energy: Float
    public let dopplerRate: Float?
    public let isApproaching: Bool
    public let latitude: Double?
    public let longitude: Double?
    public let songLabel: String?
    
    public nonisolated init(
        id: UUID = UUID(),
        sessionID: UUID = UUID(),
        timestamp: Date = .now,
        threatLabel: String,
        confidence: Double = 1.0,
        bearing: Double,
        distance: Double,
        energy: Float,
        dopplerRate: Float? = nil,
        isApproaching: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        songLabel: String? = nil          // ← NEW
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.threatLabel = threatLabel
        self.confidence = confidence
        self.bearing = bearing
        self.distance = distance
        self.energy = energy
        self.dopplerRate = dopplerRate
        self.isApproaching = isApproaching
        self.latitude = latitude
        self.longitude = longitude
        self.songLabel = songLabel
    }
}

// MARK: - UI & MapKit Extensions
extension SoundEvent {
    
    var age: TimeInterval { Date().timeIntervalSince(timestamp) }
    
    // Dynamic Lifespan based on ML certainty
    var dynamicLifespan: TimeInterval {
        return max(0.1, 6.0 * confidence)
    }
    
    var opacity: Double {
        return max(0, 1.0 - (age / dynamicLifespan))
    }
    
    var visualScale: Double {
        return confidence
    }
    
    /// Returns a coordinate for Apple MapKit
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
}
