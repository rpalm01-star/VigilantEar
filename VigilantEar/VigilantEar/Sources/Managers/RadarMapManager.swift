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
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    self?.cleanupStaleTargets()
                }
            }
        }
    }
    
    @MainActor
    func processNewEvent(_ event: SoundEvent) {
        guard event.isRevealed else {
            //AppGlobals.doLog(message: unsafe "EVENT_SKIPPED - isRevealed = false for \(event.threatLabel) Conf:\(String(format: "%.3f", event.confidence))", step: "DEBUG")
            return
        }
        
        let distanceFeet = event.distance * 1000.0
        
         AppGlobals.doLog(
         message: "EVENT_RECEIVED [\(event.threatLabel)] Conf:\(String(format: "%.3f", event.confidence)) Dist:\(Int(distanceFeet))ft Revealed:\(event.isRevealed)",
         step: "DEBUG"
         )
        
        if event.isVehicle {
            // Tuned for real cars outside your window
            let shouldCreateTrackedTarget =
            event.confidence >= 0.21 &&
            distanceFeet <= 350.0
            
            if shouldCreateTrackedTarget {
                if let existingTarget = activeTargets[event.sessionID] {
                    existingTarget.update(with: event)
                } else {
                    let newTarget = TrackedTarget(initialEvent: event)
                    activeTargets[event.sessionID] = newTarget
                    AppGlobals.doLog(
                        message: unsafe "TRACKED_TARGET_CREATED [car] Conf:\(String(format: "%.3f", event.confidence)) Dist:\(Int(distanceFeet))ft → Persistent tracking started",
                        step: "VEHICLE_TRACK"
                    )
                }
            } else {
                AppGlobals.doLog(
                    message: unsafe "VEHICLE_SKIPPED_FOR_TRACKING [car] Conf:\(String(format: "%.3f", event.confidence)) Dist:\(Int(distanceFeet))ft → Too far or too weak for persistent tracking",
                    step: "VEHICLE_TRACK"
                )
            }
        }
        else {
            if let existingTarget = activeTargets[event.sessionID] {
                existingTarget.update(with: event)
            } else {
                let newTarget = TrackedTarget(initialEvent: event)
                activeTargets[event.sessionID] = newTarget
            }
        }
    }
    
    private func cleanupStaleTargets() {
        let now = Date()
        activeTargets = activeTargets.filter { now.timeIntervalSince($0.value.lastUpdateTime) < 6.0 }
    }
    
    @MainActor
    deinit {
        updateTask?.cancel()
    }
}
