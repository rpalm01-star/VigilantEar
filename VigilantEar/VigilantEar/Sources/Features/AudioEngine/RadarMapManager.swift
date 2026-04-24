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
        if let existingTarget = activeTargets[event.sessionID] {
            existingTarget.update(with: event)
        } else {
            // Only spawn a visible target if the sound is persistent (e.g., more than just a transient click)
            // For now, let's keep the spawn but increase the 'Stale' timer
            let newTarget = TrackedTarget(initialEvent: event)
            activeTargets[event.sessionID] = newTarget
        }
        
        cleanupStaleTargets()
    }
    
    private func cleanupStaleTargets() {
        let now = Date()
        // INCREASE THIS: Wait 2.5 seconds before deleting an icon.
        // This bridges the gaps in speech and music beats.
        activeTargets = activeTargets.filter { _, target in
            now.timeIntervalSince(target.lastUpdateTime) < 2.5
        }
    }

}
