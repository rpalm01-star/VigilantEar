import Foundation
import SwiftUI

/// ViewModel responsible for managing the comet-tail history shown on the map.
///
/// It receives processed `SoundEvent`s from `AcousticProcessingPipeline`,
/// keeps only those with valid GPS coordinates, and automatically purges
/// old events based on each event’s `dynamicLifespan` (from its `SoundProfile`).
@Observable
@MainActor
class MapTrackingViewModel {
    
    // MARK: - Public State
    
    /// The full history of events currently displayed on the map as comet tails.
    /// Only events with valid GPS coordinates are stored here.
    var eventHistory: [SoundEvent] = []
    
    // MARK: - Private State
    
    /// The background task that periodically cleans up expired events.
    private var sweepingTask: Task<Void, Never>?
    
    // Optional: Limit the maximum number of events we keep in memory
    private let maxHistoryCount: Int = 800
    
    
    // MARK: - Initialization
    
    init() {
        startSweeping()
    }
    
    @MainActor
    deinit {
        sweepingTask?.cancel()
    }
    
    
    // MARK: - Public API
    
    /// Called every time the `AcousticProcessingPipeline` yields a new `SoundEvent`.
    /// Only events with valid GPS coordinates are added to the history.
    func receiveNewEvent(_ event: SoundEvent) {
        guard event.coordinate != nil else { return }
        
        eventHistory.append(event)
        
        // Optional: Keep history bounded to prevent unbounded memory growth
        if eventHistory.count > maxHistoryCount {
            eventHistory.removeFirst(eventHistory.count - maxHistoryCount)
        }
    }
    
    
    // MARK: - Private Helpers
    
    private func startSweeping() {
        sweepingTask = Task {
            await runSweeper()
        }
    }
    
    private func runSweeper() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.1))
            purgeDeadDots()
        }
    }
    
    /// Removes all events whose age exceeds their individual `dynamicLifespan`.
    private func purgeDeadDots() {
        eventHistory.removeAll { $0.age > $0.dynamicLifespan }
    }
}
