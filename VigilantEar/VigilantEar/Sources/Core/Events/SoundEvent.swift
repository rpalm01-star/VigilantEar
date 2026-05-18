import Foundation
import SwiftUI
import CoreLocation

/// A single acoustic detection event representing one "ping" from the ML pipeline.
struct SoundEvent: Identifiable {
    
    // MARK: - Identity & Grouping
    
    let id: UUID
    let sessionID: UUID
    
    // MARK: - Timing & Labeling
    
    var timestamp: Date
    var threatLabel: String
    
    var hitCount: Int = 1
    
    // MARK: - ML Confidence & Reveal Logic
    
    public let confidence: Double
    public let isRevealed: Bool
    
    // NEW: Cached profile - computed once at creation
    public let profile: SoundProfile
    
    public var trackedTarget: TrackedTarget?
    
    // MARK: - Spatial & Physics Data
    
    public let bearing: Double
    public let distance: Double
    public var energy: Float
    public let dopplerRate: Float?
    public let isApproaching: Bool
    public let latitude: Double?
    public let longitude: Double?
    public var songLabel: String?
    
    // MARK: - Initializer
    
    @MainActor public init(
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
        self.profile = SoundProfile.classify(threatLabel)
    }
    
    /// Nonisolated initializer for when a precomputed profile is available.
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
        songLabel: String? = nil,
        profile: SoundProfile
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
        self.profile = profile
    }
    
    /// Async initializer that computes the profile on the main actor and initializes off-main safely.
    public init(
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
        songLabel: String? = nil,
    ) async {
        let computedProfile = await MainActor.run { SoundProfile.classify(threatLabel) }
        self.init(
            id: id,
            sessionID: sessionID,
            timestamp: timestamp,
            threatLabel: threatLabel,
            confidence: confidence,
            bearing: bearing,
            distance: distance,
            energy: energy,
            dopplerRate: dopplerRate,
            isApproaching: isApproaching,
            latitude: latitude,
            longitude: longitude,
            isRevealed: isRevealed,
            songLabel: songLabel,
            profile: computedProfile
        )
    }
    
    // MARK: - Convenience Properties (now using cached profile)
    
    public var isMusic: Bool { profile.isMusic }
    public var isEmergency: Bool { profile.isEmergency }
    public var isVehicle: Bool { profile.isVehicle }
    public var dotColor: Color { profile.color }
    public var shouldInnerCircleReact: Bool { isEmergency }
}

// MARK: - UI & MapKit Extensions
extension SoundEvent {
    
    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
    
    var dynamicLifespan: TimeInterval {
        profile.tailMemory
    }
    
    var opacity: Double {
        max(0, 1.0 - (age / dynamicLifespan))
    }
    
    var visualScale: Double {
        confidence
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
