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
    var realThreatLabel: String
    var hitCount: Int = 1
    
    // ML Certainty (0.0 to 1.0)
    public let confidence: Double
    
    // 🧠 Centralized profile lookup to keep the properties clean
    private var profile: SoundProfile {
        return SoundProfile.classify(threatLabel)
    }
    
    public var isEmergency: Bool {
        return profile.isEmergency
    }
    
    public var isVehicle: Bool {
        return profile.isVehicle
    }
    
    // 🌫️ Fog of War gate for the UI
    public var isRevealed: Bool {
        return confidence >= profile.revealThreshold
    }
    
    // 🎨 Pulls directly from our meticulously color-coded registry!
    public var dotColor: Color {
        return profile.color
    }
    
    /// Tells the UI whether the inner circle should react (flash, pulse, change color, etc.)
    /// Currently used for all emergency events (fire trucks, sirens, etc.)
    public var shouldInnerCircleReact: Bool {
        return isEmergency
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
        realThreatLabel: String,
        confidence: Double = 1.0,
        bearing: Double,
        distance: Double,
        energy: Float,
        dopplerRate: Float? = nil,
        isApproaching: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        songLabel: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.threatLabel = threatLabel
        self.realThreatLabel = realThreatLabel
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
    
    // ⏳ Ties the visual fade directly to the physics engine's memory!
    var dynamicLifespan: TimeInterval {
        return SoundProfile.classify(threatLabel).tailMemory
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
