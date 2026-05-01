import Foundation

/// A lightweight container for **raw ML classification results**.
///
/// Unlike `SoundEvent` (which is the fully processed, physics-aware event used on the map and HUD),
/// `SoundLabelEvent` is used **only** by the `NeuralTickerHUD` — the small scrolling ticker
/// that shows every label the CoreML model returns in real time.
///
/// This struct exists so we can:
/// - Keep raw ML output separate from processed threat data
/// - Easily throttle or filter what appears in the neural ticker
/// - Send lightweight telemetry to Firestore if needed
struct SoundLabelEvent {
    
    /// The exact label returned by the SoundAnalysis / CoreML classifier
    /// (e.g. "siren", "car_passing_by", "speech", "dog_bark", etc.).
    let rawMLSoundLabel: String
    
    /// When this label was first received from the ML pipeline.
    var creationTime: Date
    
    /// The confidence at the time the label was created.
    var confidence: Double
    
    
    // MARK: - Initializer
    
    public nonisolated init(rawMLSoundLabel: String, creationTime: Date, confidence: Double) {
        self.rawMLSoundLabel = rawMLSoundLabel
        self.creationTime = creationTime
        self.confidence = confidence
    }
}
