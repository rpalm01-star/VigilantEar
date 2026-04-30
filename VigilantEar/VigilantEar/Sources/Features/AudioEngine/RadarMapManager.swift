import Foundation
import Observation

@Observable
class RadarMapManager {
    
    private var activeTargets: [UUID: TrackedTarget] = [:]
    var visibleTargets: [TrackedTarget] { Array(activeTargets.values) }
    
    private var updateTask: Task<Void, Never>?
    
    init() {
        startUpdateLoop()
    }
    
    private func startUpdateLoop() {
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                await MainActor.run {
                    self?.cleanupStaleTargets()
                }
            }
        }
    }
    
    @MainActor
    func processNewEvent(_ event: SoundEvent) {
        guard event.isRevealed else { return }
        
        if let existingTarget = activeTargets[event.sessionID] {
            existingTarget.update(with: event)
        } else {
            let newTarget = TrackedTarget(initialEvent: event)
            activeTargets[event.sessionID] = newTarget
        }
    }
    
    private func cleanupStaleTargets() {
        let now = Date()
        activeTargets = activeTargets.filter { now.timeIntervalSince($0.value.lastUpdateTime) < 6.0 }
    }
    
    deinit {
        updateTask?.cancel()
    }
}
