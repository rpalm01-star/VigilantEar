import SwiftUI
import CoreLocation

@Observable
final class SoundEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let classification: String
    let confidence: Float
    
    // Direction & proximity from TDOA + Doppler
    let angle: Double?          // degrees (0° = straight ahead, positive = clockwise)
    let proximity: Double       // 0.0 (far) → 1.0 (very close)
    
    // Computed visualization properties for RadarView
    var radialProximity: Double {
        proximity
    }
    
    var visualSize: CGFloat {
        CGFloat(20 + (proximity * 60))
    }
    
    var color: Color {
        switch classification.lowercased() {
        case "siren", "emergency", "police":
            return .red
        case "motorcycle", "engine", "car":
            return .orange
        case "horn", "car_horn":
            return .yellow
        default:
            return .blue
        }
    }
    
    var isAmbient: Bool {
        confidence < 0.6
    }
    
    // Optional location (for logging / Google Maps)
    var location: CLLocationCoordinate2D?
    
    init(
        timestamp: Date = Date(),
        classification: String,
        confidence: Float,
        angle: Double? = nil,
        proximity: Double,
        location: CLLocationCoordinate2D? = nil
    ) {
        self.timestamp = timestamp
        self.classification = classification
        self.confidence = confidence
        self.angle = angle
        self.proximity = proximity
        self.location = location
    }
}
