import Foundation
import Observation

// 🚀 OPTIMIZATION: Lock the entire class to the MainActor for UI safety
@MainActor
@Observable
class MapManager {
    
    private var activeTargets: [UUID: TrackedTarget] = [:]
    var visibleTargets: [TrackedTarget] { Array(activeTargets.values) }
    
    private var updateTask: Task<Void, Never>?
    
    init() {
        startUpdateLoop()
    }
    
    private func startUpdateLoop() {
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
                self?.cleanupStaleTargets()
            }
        }
    }
    
    func processNewEvent(_ event: SoundEvent) {
        // 1. The Gatekeeper: Respects your SoundProfile registry!
        guard event.isRevealed else { return }
        
        let distanceFeet = event.distance * 1000.0
        
        AppGlobals.doLog(message: "🚗 Revealed: [\(event.threatLabel)] Conf:\(String(format: "%.3f", event.confidence)) Dist:\(Int(distanceFeet))ft Revealed:true",
                         step: "MapManager.processNewEvent")
        
        // 2. Target Creation (Unified for ALL sounds)
        if let existingTarget = activeTargets[event.sessionID] {
            existingTarget.update(with: event)
        } else {
            let newTarget = TrackedTarget(initialEvent: event)
            activeTargets[event.sessionID] = newTarget
            
            // 3. Keep your custom logging for vehicle debugging
            if event.isVehicle {
                AppGlobals.doLog(message: "🚗 New Tracked Target: [\(event.threatLabel)] Conf:\(String(format: "%.3f", event.confidence)) Dist:\(Int(distanceFeet))ft → Persistent tracking started", step: "MapManager.processNewEvent"
                )
            }
        }
    }
    
    private func cleanupStaleTargets() {
        let now = Date()
        activeTargets = activeTargets.filter { now.timeIntervalSince($0.value.lastUpdateTime) < 6.0 }
    }
    
}
