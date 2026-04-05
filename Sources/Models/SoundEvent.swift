import Foundation

/// A thread-safe data model representing a captured acoustic event.
struct SoundEvent: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let classification: String
    let confidence: Float
    let angle: Double
    let proximity: Double
    let decibels: Float
    let frequency: Double
    
    init(
        id: UUID = UUID(),
        timestamp: Date,
        classification: String,
        confidence: Float,
        angle: Double,
        proximity: Double,
        decibels: Float,
        frequency: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.classification = classification
        self.confidence = confidence
        self.angle = angle
        self.proximity = proximity
        self.decibels = decibels
        self.frequency = frequency
    }
}
