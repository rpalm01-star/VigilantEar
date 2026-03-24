import Foundation
import Observation
import MapKit
import CoreLocation
import SwiftUI

@MainActor
@Observable
class AcousticCoordinator {
    // This array holds the live "objects" currently on the radar (Used for your HUD)
    var activeEvents: [SoundEvent] = []
    
    // --- THE NEW MAP MANAGER ---
    // This holds the smoothed, physics-based targets (Used for MapKit)
    var mapManager = MapManager()
    
    /// The most recent verified threat
    var latestEvent: SoundEvent?
    
    /// Current listening status
    var isTracking: Bool = false
    
    // THE FIX: Add this to hold the simulation path
    var simulatedRoute: MKRoute? = nil
    
    // The new variable your SwiftUI views will read from
    var activeSong: String? = nil
    
    // 🚀 OPTIMIZATION: Replaced Timer with a self-canceling Task
    private var streamTask: Task<Void, Never>?
    private var songTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var isCleaning: Bool = false
    
    init() {
        startHeartbeat()
    }
    
    private func startHeartbeat() {
        // 🚀 OPTIMIZATION: Modern Swift async cleanup loop
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                self?.refreshRadar()
            }
        }
    }
    
    private func refreshRadar() {
        if activeEvents.isEmpty || isCleaning { return }
        
        isCleaning = true
        let now = Date()
        
        // Keep the trail on the screen for 5 seconds
        let updated = activeEvents.filter { now.timeIntervalSince($0.timestamp) < 5.0 }
        
        if updated.count != activeEvents.count {
            self.activeEvents = updated
        }
        isCleaning = false
    }
    
    func addEvent(_ event: SoundEvent) {
        activeEvents.append(event)
        mapManager.processNewEvent(event)
    }
    
    func startListeningToPipeline(_ pipeline: AcousticProcessingPipeline) {
        isTracking = true
        
        streamTask = Task {
            for await event in pipeline.eventStream {
                activeEvents.append(event)
                self.latestEvent = event
                self.mapManager.processNewEvent(event)
            }
        }
        
        // Listen for Shazam Song Matches
        songTask = Task {
            for await songTitle in pipeline.songStream {
                // Task inherits @MainActor from the class, so we don't need MainActor.run here
                withAnimation(.spring()) {
                    self.activeSong = songTitle
                }
            }
        }
    }
    
    func stopListening() {
        streamTask?.cancel()
        streamTask = nil
        songTask?.cancel()
        songTask = nil
        
        isTracking = false
        activeEvents.removeAll()
        mapManager = MapManager()
    }
    
    deinit {
        //cleanupTask?.cancel()
    }
}
