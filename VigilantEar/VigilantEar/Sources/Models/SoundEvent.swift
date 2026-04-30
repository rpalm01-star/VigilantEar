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
    
    // 🛡️ THE REVEAL GATE: Now a stored property so the pipeline can force it to true/false
    public let isRevealed: Bool
    
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
    
    // 🎨 Pulls directly from our meticulously color-coded registry!
    public var dotColor: Color {
        return profile.color
    }
    
    /// Tells the UI whether the inner circle should react (flash, pulse, change color, etc.)
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
        confidence: Double = 1.0,
        bearing: Double,
        distance: Double,
        energy: Float,
        dopplerRate: Float? = nil,
        isApproaching: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isRevealed: Bool,
        songLabel: String? = nil
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
        self.isRevealed = isRevealed
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
