import Foundation
import SwiftUI

@Observable
@MainActor
class MapTrackingViewModel {
    // ☄️ This array holds the entire comet tail history!
    var eventHistory: [SoundEvent] = []
    
    init() {
        // 🧹 The Modern Swift 6 Janitor
        Task {
            await startSweeping()
        }
    }
    
    private func startSweeping() async {
        // Runs continuously, sweeping 10 times a second
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.1))
            purgeDeadDots()
        }
    }
    
    // Call this every time the AcousticProcessingPipeline yields a new event
    func receiveNewEvent(_ event: SoundEvent) {
        // Only add it to the map if it actually has GPS coordinates
        if event.coordinate != nil {
            eventHistory.append(event)
        }
    }
    
    private func purgeDeadDots() {
        // Automatically deletes any dot whose age exceeds its tailMemory!
        eventHistory.removeAll { $0.age > $0.dynamicLifespan }
    }
}
