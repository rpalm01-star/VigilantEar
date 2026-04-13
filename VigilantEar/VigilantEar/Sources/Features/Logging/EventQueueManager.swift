//
//  EventQueueManager.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/12/26.
//

import SwiftData
import Foundation

actor EventQueueManager {
    private let modelContainer: ModelContainer
    
    init(container: ModelContainer) {
        self.modelContainer = container
    }
    
    /// Pulls items off the local SwiftData queue and processes them
    func flushQueue() async {
        // 1. Create a background context for the database
        let context = ModelContext(modelContainer)
                
        // 2. Query only the items sitting in the queue
        // We now query against the raw integer, bypassing the SwiftData enum bug!
        let queuedRaw = EventSyncStatus.queued.rawValue
        
        let fetchDescriptor = FetchDescriptor<SoundEvent>(
            predicate: #Predicate { $0.syncStatusRaw == queuedRaw },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)] // Oldest first
        )
        
        do {
            let pendingEvents = try context.fetch(fetchDescriptor)
            guard !pendingEvents.isEmpty else { return }
            
            print("Found \(pendingEvents.count) events in the queue.")
            
            // 3. Mark them as processing so another thread doesn't grab them
            for event in pendingEvents {
                event.syncStatus = .processing
            }
            try context.save()
            
            // 4. Do whatever you decide to do with them!
            // (e.g., send to server, write to a log file, ML analysis)
            let success = await processEvents(pendingEvents)
            
            // 5. Update their final status
            for event in pendingEvents {
                event.syncStatus = success ? .completed : .failed
            }
            
            try context.save()
            print("Queue flush complete.")
            
        } catch {
            print("Failed to access local queue: \(error)")
        }
    }
    
    /// Replaces the old dummy function with actual JSON file export
    private func processEvents(_ events: [SoundEvent]) async -> Bool {
        guard !events.isEmpty else { return true }
        
        // 1. Map the SwiftData models into simple, encodable dictionaries
        let exportPayload = events.map { event in
            return [
                "id": event.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                "threatLabel": event.threatLabel,
                "isEmergency": event.isEmergency,
                "bearing": event.bearing,
                "distance": event.distance,
                "energy": event.energy,
                "dopplerRate": event.dopplerRate ?? 0.0
            ] as [String : Any]
        }
        
        do {
            // 2. Convert to JSON Data
            let jsonData = try JSONSerialization.data(withJSONObject: exportPayload, options: .prettyPrinted)
            
            // 3. Find the iOS Documents Directory
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            
            // 4. Create a unique filename for this specific batch
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = "VigilantEar_Log_\(formatter.string(from: Date())).json"
            
            let fileURL = documentsDirectory.appendingPathComponent(filename)
            
            // 5. Write the file to disk
            try jsonData.write(to: fileURL)
            
            print("✅ Successfully exported \(events.count) events to \(fileURL.path)")
            print("📂 MAC FINDER PATH: \(fileURL.path)")
            return true
            
        } catch {
            print("❌ Failed to process events to JSON: \(error.localizedDescription)")
            return false
        }
    }
}
