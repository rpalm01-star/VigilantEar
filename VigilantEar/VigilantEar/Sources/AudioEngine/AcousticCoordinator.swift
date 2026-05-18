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
        if (isTracking) {
            AppGlobals.doLog(message: "Bypassed pipeline listener start attempt because it was already started.", step: "AcousticCoordinator")
            return
        }
        
        isTracking = true
        AppGlobals.doLog(message: "Started listening to pipeline", step: "AcousticCoordinator")
        
        // Listen for regular streaming sound events.
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
                    // Bind the song title directly to the latest music SoundEvent
                    if let index = self.activeEvents.lastIndex(where: { $0.isMusic }) {
                        self.activeEvents[index].songLabel = songTitle
                    }
                }
            }
        }
    }
    
    func getCurrentSongName() -> String {
        var songName = activeEvents.last(where: { $0.isMusic })?.songLabel ?? String.empty
        songName = songName
            .replacingOccurrences(of: "♫", with: String.empty)
            .replacingOccurrences(of: "🎵", with: String.empty)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return songName
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
