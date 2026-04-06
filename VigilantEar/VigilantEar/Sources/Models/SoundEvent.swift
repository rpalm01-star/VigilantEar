import Foundation

struct SoundEvent: Identifiable {
    let id = UUID()                     // ← this guarantees every dot is unique
    
    let timestamp: Date
    let classification: String
    let confidence: Float
    let angle: Double
    let proximity: Double
    let decibels: Float
    let frequency: Double
}
