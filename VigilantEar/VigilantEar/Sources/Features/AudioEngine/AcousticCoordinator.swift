import Foundation
import Observation

@MainActor
@Observable
class AcousticCoordinator {
    // This array holds the live "objects" currently on the radar
    var activeEvents: [SoundEvent] = []
    /// The most recent verified threat
    var latestEvent: SoundEvent?
    /// Current listening status
    var isTracking: Bool = false
    // Is the cleanup running?
    var isCleaning: Bool = false;
    
    // Task to manage the async stream lifecycle
    private var streamTask: Task<Void, Never>?
    private var cleanupTimer: Timer?

    init() {
        startHeartbeat()
    }

    private func startHeartbeat() {
        // Independent loop: Prunes the radar 5 times a second
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshRadar()
            }
        }
    }

    @MainActor
    private func refreshRadar() {
        if (activeEvents.isEmpty)
        {
            return;
        }
        if (isCleaning) {
            print("❌ Active event cleanup is already running. Bypassing.")
            return
        }
        isCleaning = true
        let now = Date()
        let updated = activeEvents.filter { event in
            now.timeIntervalSince(event.timestamp) < 2.0
        }
        if updated.count != activeEvents.count {
            self.activeEvents = updated
        }
        isCleaning = false
    }
    
    @MainActor
    func addEvent(_ event: SoundEvent) {
        // Because every 'bell' ring creates a NEW SoundEvent() instance
        // with a NEW UUID, they will overlap and pulse correctly.
        activeEvents.append(event)
    }
    
    func startListeningToPipeline(_ pipeline: AcousticProcessingPipeline) {
        isTracking = true
        streamTask = Task {
            for await event in pipeline.eventStream {
                activeEvents.append(event)
                self.latestEvent = event
            }
        }
    }
    
    func stopListening() {
        streamTask?.cancel()
        streamTask = nil
        isTracking = false
        activeEvents.removeAll()
    }
}
