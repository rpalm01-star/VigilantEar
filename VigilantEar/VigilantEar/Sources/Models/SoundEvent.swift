import Foundation
import SwiftData
import CoreLocation

@Model
public final class SoundEvent {
    
    // MARK: - Core Identity
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var threatLabel: String
    
    // MARK: - Spatial & Acoustic Metrics
    /// The calculated Angle of Arrival (AoA) in degrees (0.0 to 180.0)
    public var bearing: Double
    
    // The distance from the reference point
    public var distance: Double
    
    /// The rate of frequency change in Hz/sec. Nil if the shift was negligible.
    public var dopplerRate: Float?
    
    /// True if the frequency is blue-shifting (increasing), indicating a collision course.
    public var isApproaching: Bool
    
    // MARK: - GIS Location Data
    // Stored as optional Doubles because we might detect a threat before the GPS gets a precise lock
    public var latitude: Double?
    public var longitude: Double?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        threatLabel: String,
        bearing: Double,
        distance: Double,
        dopplerRate: Float? = nil,
        isApproaching: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.threatLabel = threatLabel
        self.bearing = bearing
        self.distance = distance
        self.dopplerRate = dopplerRate
        self.isApproaching = isApproaching
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Computed Properties for the UI
extension SoundEvent {
    
    /// Returns a coordinate for the Google Maps SDK
    @Transient
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    /// Formats the Doppler shift for the UI
    @Transient
    var formattedDoppler: String {
        guard let rate = dopplerRate else { return "Stable" }
        let direction = isApproaching ? "Approaching" : "Receding"
        return "\(direction) (\(String(format: "%.1f", rate)) Hz/s)"
    }
}
