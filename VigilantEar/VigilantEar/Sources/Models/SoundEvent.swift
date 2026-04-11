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
    
    /// The calculated Angle of Arrival (AoA) in degrees (-90.0 to 90.0)
    public var bearing: Double
    
    /// The physical distance of the threat, driven dynamically by Doppler velocity
    public var distance: Double
    
    /// The normalized RMS energy (0.0 to 1.0) used for UI scale and opacity fading
    public var energy: Float
    
    /// The relative velocity in meters per second (m/s). Nil if the shift was negligible.
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
        energy: Float,
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
        self.energy = energy
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
    
    /// Formats the Doppler velocity for the UI
    @Transient
    var formattedDoppler: String {
        guard let rate = dopplerRate, abs(rate) > 0.1 else { return "Stationary" }
        let direction = isApproaching ? "Approaching" : "Receding"
        
        // Formatted to show meters per second
        return "\(direction) (\(String(format: "%.1f", abs(rate))) m/s)"
    }
}
