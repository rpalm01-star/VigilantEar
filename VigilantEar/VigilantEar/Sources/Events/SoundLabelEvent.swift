import Foundation

struct SoundLabelEvent {
    let rawMLSoundLabel: String
    var creationTime: Date
    
    public nonisolated init(rawMLSoundLabel: String, creationTime: Date) {
        self.rawMLSoundLabel = rawMLSoundLabel
        self.creationTime = creationTime
    }
}
