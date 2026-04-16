import Foundation
import SwiftUI
import CoreLocation

// NOTE: SwiftData is gone! This is now a pure, thread-safe value type.
struct SoundEvent: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let threatLabel: String
    public let isEmergency: Bool
    
    // MARK: - Spatial Data
    public let bearing: Double
    public let distance: Double
    public let energy: Float
    public let dopplerRate: Float?
    public let isApproaching: Bool
    
    public let latitude: Double?
    public let longitude: Double?
    
    public nonisolated init(
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
        
        let lowercased = threatLabel.lowercased()
        self.isEmergency = lowercased.contains("siren") ||
        lowercased.contains("ambulance") ||
        lowercased.contains("fire")
    }
}

// MARK: - UI & MapKit Extensions
extension SoundEvent {
    
    var age: TimeInterval { Date().timeIntervalSince(timestamp) }
    
    var opacity: Double {
        return max(0, 1.0 - (age / 2.0))
    }
    
    /// Returns a coordinate for Apple MapKit
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    /// Formats the Doppler velocity for the UI
    var formattedDoppler: String {
        guard let rate = dopplerRate, abs(rate) > 0.1 else { return "Stationary" }
        let direction = isApproaching ? "Approaching" : "Receding"
        
        // Formatted to show meters per second
        return "\(direction) (\(String(format: "%.1f", abs(rate))) m/s)"
    }
    
    /// Instantly maps the pre-calculated boolean to a UI Color.
    var dotColor: Color {
        return isEmergency ? VigilantTheme.emergencyDot : VigilantTheme.standardDot
    }
}
