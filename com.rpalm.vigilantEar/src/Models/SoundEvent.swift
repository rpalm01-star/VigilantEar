import Foundation
import SwiftUI

// In RadarView.swift, apply the blur for ambient blobs
Circle()
    .fill(event.color)
    .opacity(event.isAmbient ? 0.3 : 1.0)
    .blur(radius: event.isAmbient ? 10 : 0) // The "Blob" effect


struct SoundEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    
    // Raw Acoustic Data
    var decibels: Float        // -160 to 0
    var frequency: Double      // Hz
    var confidence: Double     // 0.0 to 1.0 (from Core ML)
    var classification: String // "Motorcycle", "Siren", etc.
    
    // Positional Logic (Calculated)
    var angle: Double          // 0 to 360 (TDOA)
    
    /// Maps dB to a radial distance from the center (0.0 is center, 1.0 is border)
    var radialProx: Double {
        // Normalizing dB to a 0-1 scale where louder is closer (smaller value)
        let normalized = Double((decibels + 100) / 100) 
        return max(0.0, min(1.0, 1.0 - normalized))
    }
    
    /// Maps proximity to visual size (Bigger when closer to center)
    var visualSize: CGFloat {
        let minSize: CGFloat = 12.0
        let maxSize: CGFloat = 60.0
        // As radialProx approaches 0 (center), size approaches maxSize
        return maxSize - (CGFloat(radialProx) * (maxSize - minSize))
    }
    
    var color: Color {
        switch classification.lowercased() {
        case "siren": return .red
        case "motorcycle": return .orange
        default: return .gray
        }
    }
    
    // Add to the SoundEvent struct
    var isAmbient: Bool {
        return confidence < 0.4 || classification == "background_noise"
    }

}
