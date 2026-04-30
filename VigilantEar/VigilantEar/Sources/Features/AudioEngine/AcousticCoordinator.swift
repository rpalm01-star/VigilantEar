import Foundation
import Observation
import MapKit
import CoreLocation // Required for the coordinate math that feeds MKRoute
import SwiftUI

@MainActor
@Observable
class AcousticCoordinator {
    // This array holds the live "objects" currently on the radar (Used for your HUD)
    var activeEvents: [SoundEvent] = []
    
    // --- THE NEW MAP MANAGER ---
    // This holds the smoothed, physics-based targets (Used for MapKit)
    var mapManager = RadarMapManager()
    
    /// The most recent verified threat
    var latestEvent: SoundEvent?
    
    /// Current listening status
    var isTracking: Bool = false
    
    // Is the cleanup running?
    var isCleaning: Bool = false
    
    // THE FIX: Add this to hold the simulation path
    var simulatedRoute: MKRoute? = nil
    
    // Task to manage the async stream lifecycle
    private var streamTask: Task<Void, Never>?
    
    private var cleanupTimer: Timer?
    
    // The new variable your SwiftUI views will read from
    var activeSong: String? = nil
    
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
        if (activeEvents.isEmpty) { return }
        
        if (isCleaning) {
            return
        }
        isCleaning = true
        let now = Date()
        // Keep the trail on the screen for 5 seconds
        let updated = activeEvents.filter { event in
            now.timeIntervalSince(event.timestamp) < 5.0
        }
        if updated.count != activeEvents.count {
            self.activeEvents = updated
        }
        isCleaning = false
    }
    
    @MainActor
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
        Task {
            for await songTitle in pipeline.songStream {
                await MainActor.run {
                    // Simply update the song. We don't need a timer here anymore!
                    withAnimation(.spring()) {
                        self.activeSong = songTitle
                    }
                }
            }
        }
    }
    
    func stopListening() {
        streamTask?.cancel()
        streamTask = nil
        isTracking = false
        activeEvents.removeAll()
        mapManager = RadarMapManager()
    }
    
}
