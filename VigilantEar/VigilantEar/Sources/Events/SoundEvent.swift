import Foundation
import SwiftUI
import CoreLocation

/// A single acoustic detection event representing one "ping" from the ML pipeline.
///
/// `SoundEvent` is the core data model passed between:
/// - The acoustic processing pipeline (`AcousticProcessingPipeline`)
/// - The map / HUD views (`MapView`, `ThreatMarker`, `NeuralTickerHUD`)
/// - Firestore telemetry
///
/// It carries both raw sensor data and computed visual/physics properties.
struct SoundEvent: Identifiable {
    
    // MARK: - Identity & Grouping
    
    /// Unique identifier used **only for UI rendering**.
    ///
    /// A brand new `UUID` is generated on every update so MapKit can draw
    /// smooth comet-tail / trail effects. **Do not use this for persistence.**
    let id: UUID
    
    /// Shared session identifier that groups an entire "drive-by" together.
    ///
    /// All `SoundEvent`s belonging to the same vehicle/siren have the same `sessionID`.
    /// This is the ID used for Firestore, `TrackedTarget`, and multi-target tracking.
    let sessionID: UUID
    
    
    // MARK: - Timing & Labeling
    
    var timestamp: Date
    
    /// The canonical label returned by the ML classifier (e.g. "siren", "car", "speech").
    var threatLabel: String
    
    /// How many times this exact `sessionID` has been detected so far.
    var hitCount: Int = 1
    
    
    // MARK: - ML Confidence & Reveal Logic
    
    /// ML model confidence score (0.0 – 1.0).
    public let confidence: Double
    
    /// **The Reveal Gate** — determines whether this event should be shown to the user.
    ///
    /// - `true`  → Event is visible on map, HUD, and can trigger alerts/haptics.
    /// - `false` → Event is tracked in the background only (ghost mode).
    ///
    /// Set by `AcousticProcessingPipeline` based on `leadInTime` + `minimumConfidence`.
    public let isRevealed: Bool
    
    
    // MARK: - Computed Profile Properties
    
    /// Centralized profile lookup. Keeps the struct clean and ensures
    /// we always use the latest registry values.
    private var profile: SoundProfile {
        return SoundProfile.classify(threatLabel)
    }
    
    /// Whether this event belongs to an emergency category (siren, alarm, etc.).
    public var isEmergency: Bool {
        return profile.isEmergency
    }
    
    /// Whether this event belongs to a vehicle category (car, truck, motorcycle, etc.).
    public var isVehicle: Bool {
        return profile.isVehicle
    }
    
    /// The color associated with this threat type (from the registry).
    public var dotColor: Color {
        return profile.color
    }
    
    /// Tells the UI whether the inner ring / proximity animation should react.
    public var shouldInnerCircleReact: Bool {
        return isEmergency
    }
    
    
    // MARK: - Spatial & Physics Data
    
    /// Bearing in degrees relative to the user’s heading (-90° … +90°).
    public let bearing: Double
    
    /// Normalized distance (0.0 – 1.0) used for UI scaling.
    public let distance: Double
    
    /// Raw audio energy / amplitude at the time of detection.
    public var energy: Float
    
    /// Doppler shift in Hz (positive = approaching, negative = receding).
    public let dopplerRate: Float?
    
    /// Whether the source is moving toward the user.
    public let isApproaching: Bool
    
    /// Optional GPS coordinates of the estimated source location.
    public let latitude: Double?
    public let longitude: Double?
    
    /// Optional song title/artist if this event was identified via Shazam.
    public let songLabel: String?
    
    
    // MARK: - Initializer
    
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
    
    /// Age of this event in seconds.
    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
    
    /// How long this event should remain visible on screen (from the profile).
    var dynamicLifespan: TimeInterval {
        return SoundProfile.classify(threatLabel).tailMemory
    }
    
    /// Opacity used for fading comet tails and ghost icons.
    var opacity: Double {
        return max(0, 1.0 - (age / dynamicLifespan))
    }
    
    /// Visual scale factor based on ML confidence.
    var visualScale: Double {
        return confidence
    }
    
    /// Convenience coordinate for MapKit annotations.
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
