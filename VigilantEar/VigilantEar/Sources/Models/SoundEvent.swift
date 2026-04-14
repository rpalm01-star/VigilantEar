import Foundation
import SwiftData
import SwiftUI
import CoreLocation

// A simple state machine for your queue
public enum EventSyncStatus: Int, Codable {
    case queued = 0      // Sitting locally, waiting for action
    case processing = 1  // Currently being handled (prevents double-processing)
    case completed = 2   // Done! (Archived or ready for deletion)
    case failed = 3      // Attempted to process but failed
}

@Model
final class SoundEvent: @unchecked Sendable {
    @Attribute(.unique) public var id: UUID
    
    public var timestamp: Date
    public var threatLabel: String
    public var isEmergency: Bool
    
    // MARK: - Queue State
    
    /// This is the actual Integer stored in SQLite
    public var syncStatusRaw: Int = 0
    
    /// This is the nice Enum used by the UI/Logic (not stored in DB)
    @Transient
    public var syncStatus: EventSyncStatus {
        get { return EventSyncStatus(rawValue: syncStatusRaw) ?? .queued }
        set { syncStatusRaw = newValue.rawValue }
    }
    
    // MARK: - Spatial Data
    
    public var bearing: Double
    public var distance: Double
    public var energy: Float
    public var dopplerRate: Float?
    public var isApproaching: Bool
    
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
        
        let lowercased = threatLabel.lowercased()
        self.isEmergency = lowercased.contains("siren") ||
        lowercased.contains("ambulance") ||
        lowercased.contains("fire")
        
        // Initialize the raw value for the database
        self.syncStatusRaw = EventSyncStatus.queued.rawValue
    }
}

extension SoundEvent {
    
    @Transient
    var age: TimeInterval { Date().timeIntervalSince(timestamp) }
    
    @Transient
    var opacity: Double {
        return max(0, 1.0 - (age / 2.0))
    }
    
    /// Returns a coordinate for the Google Maps SDK
    @Transient
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    /// Formats the Doppler velocity for the UI
    @Transient
    var formattedDoppler: String {
        guard let rate = dopplerRate, abs(rate) > 0.1 else { return "Stationary" }
        let direction = isApproaching ? "Approaching" : "Receding"
        
        // Formatted to show meters per second
        return "\(direction) (\(String(format: "%.1f", abs(rate))) m/s)"
    }
    
    /// Instantly maps the pre-calculated boolean to a UI Color.
    /// Marked @Transient so SwiftData knows not to attempt to save a SwiftUI.Color to SQLite.
    @Transient
    var dotColor: Color {
        return isEmergency ? VigilantTheme.emergencyDot : VigilantTheme.standardDot
    }
    
}
