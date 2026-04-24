//
//  RadarMapManager.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/23/26.
//


import Foundation
import Observation

@Observable
class RadarMapManager {
    
    // The internal dictionary keeping track of every active vehicle by its UUID
    private var activeTargets: [UUID: TrackedTarget] = [:]
    
    // The clean array exposed to your SwiftUI Map loop
    var visibleTargets: [TrackedTarget] {
        Array(activeTargets.values)
    }
    
    @MainActor
    func processNewEvent(_ event: SoundEvent) {
        // Skip events with no GPS coordinates (environmental noise, UI clicks, etc.)
        guard event.latitude != nil, event.longitude != nil else { return }
        
        if let existingTarget = activeTargets[event.sessionID] {
            // The car is already on the map! Feed it the new data so it glides forward
            existingTarget.update(with: event)
        } else {
            // A completely new vehicle just appeared on the radar
            let newTarget = TrackedTarget(initialEvent: event)
            activeTargets[event.sessionID] = newTarget
        }
        
        // Clean up ghosts: Remove any target that hasn't made a sound in 4 seconds
        cleanupStaleTargets()
    }
    
    private func cleanupStaleTargets() {
        let now = Date()
        activeTargets = activeTargets.filter { _, target in
            now.timeIntervalSince(target.lastUpdateTime) < 4.0
        }
    }
}