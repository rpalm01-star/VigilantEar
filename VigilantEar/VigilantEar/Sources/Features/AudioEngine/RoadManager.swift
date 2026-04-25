//  RoadManager.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/25/26.
//

@preconcurrency import Foundation
@preconcurrency import CoreLocation
import Observation

// MARK: - OSM Decoding Models
nonisolated struct OSMResponse: Decodable, Sendable {
    let elements: [OSMElement]
}

nonisolated struct OSMElement: Decodable, Sendable {
    let type: String
    let geometry: [OSMNode]
}

nonisolated struct OSMNode: Decodable, Sendable {
    let lat: Double
    let lon: Double
}

@MainActor
@Observable
final class RoadManager {
    
    var cachedRoadSegments: [[CLLocationCoordinate2D]] = []
    
    private var lastCacheAnchor: CLLocation?
    private var settleTask: Task<Void, Never>?
    private var highSpeedTicks: Int = 0
    private(set) var isFetching: Bool = false // <-- THE TWEAK
    
    func processLocationUpdate(_ location: CLLocation) {
        guard !isFetching else { return }
        
        guard let anchor = lastCacheAnchor else {
            fetchRoadSector(at: location)
            return
        }
        
        let distance = location.distance(from: anchor)
        if distance < 300 { return }
        
        if location.speed > 8.0 {
            highSpeedTicks += 1
            cancelSettling()
            return
        }
        
        if location.speed <= 3.0 && settleTask == nil {
            startSettlingTimer(at: location)
        }
    }
    
    private func startSettlingTimer(at location: CLLocation) {
        let dynamicPenalty = min(highSpeedTicks * 2, 60)
        let waitTimeInSeconds = 3 + dynamicPenalty
        
        AppGlobals.doLog(
            message: "🌍 RoadManager: Out of bounds. Settling for \(waitTimeInSeconds)s before network fetch...",
            step: "ROADMGR"
        )
        
        settleTask = Task {
            do {
                try await Task.sleep(for: .seconds(waitTimeInSeconds))
                fetchRoadSector(at: location)
            } catch {
                AppGlobals.doLog(
                    message: "🌍 RoadManager: Settling interrupted. User resumed moving.",
                    step: "ROADMGR"
                )
            }
        }
    }
    
    private func cancelSettling() {
        settleTask?.cancel()
        settleTask = nil
    }
    
    private func fetchRoadSector(at location: CLLocation) {
        isFetching = true
        cancelSettling()
        
        Task.detached(priority: .background) {
            let radiusMeters = 400
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude
            
            let query = """
            [out:json];
            way["highway"~"motorway|trunk|primary|secondary|tertiary|unclassified|residential"](around:\(radiusMeters),\(lat),\(lon));
            out geom;
            """
            
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://overpass-api.de/api/interpreter?data=\(encodedQuery)") else {
                await self.resetFetchState()
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(OSMResponse.self, from: data)
                
                var newSegments: [[CLLocationCoordinate2D]] = []
                for element in decoded.elements {
                    let coords = element.geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    newSegments.append(coords)
                }
                
                await self.updateCache(segments: newSegments, newAnchor: location)
                
            } catch {
                AppGlobals.doLog(
                    message: "🌍⚠️ RoadManager: Sector fetch failed: \(error.localizedDescription)",
                    step: "ROADMGR"
                )
                await self.resetFetchState()
            }
        }
    }
    
    private func updateCache(segments: [[CLLocationCoordinate2D]], newAnchor: CLLocation) {
        self.cachedRoadSegments = segments
        self.lastCacheAnchor = newAnchor
        self.highSpeedTicks = 0
        self.isFetching = false
        
        AppGlobals.doLog(
            message: "✅ RoadManager: New 1,300ft sector cached. (\(segments.count) roads found).",
            step: "ROADMGR"
        )
    }
    
    private func resetFetchState() {
        self.isFetching = false
    }
}
