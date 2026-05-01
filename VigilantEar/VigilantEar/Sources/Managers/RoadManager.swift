//  RoadManager.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/25/26.
//

@preconcurrency import Foundation
@preconcurrency import CoreLocation
import Observation
import MapKit

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
            
            // THE TWEAK: Adding a 5-second timeout directly into the query string for the Overpass server
            let query = """
            [out:json][timeout:5];
            way["highway"~"motorway|trunk|primary|secondary|tertiary|unclassified|residential"](around:\(radiusMeters),\(lat),\(lon));
            out geom;
            """
            
            guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://overpass-api.de/api/interpreter?data=\(encodedQuery)") else {
                await self.resetFetchState()
                return
            }
            
            // THE FIX: Custom URLSession with a hard limit so it fails fast instead of hanging
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 6.0
            config.timeoutIntervalForResource = 6.0
            let session = URLSession(configuration: config)
            
            // THE FIX: A silent 3-attempt retry loop
            var attempt = 1
            let maxAttempts = 3
            
            while attempt <= maxAttempts {
                do {
                    let (data, _) = try await session.data(from: url)
                    let decoded = try JSONDecoder().decode(OSMResponse.self, from: data)
                    
                    var newSegments: [[CLLocationCoordinate2D]] = []
                    for element in decoded.elements {
                        let coords = element.geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                        newSegments.append(coords)
                    }
                    
                    await self.updateCache(segments: newSegments, newAnchor: location)
                    return // Success! Exit the loop and task.
                    
                } catch {
                    if attempt == maxAttempts {
                        AppGlobals.doLog(
                            message: "🌍⚠️ RoadManager: Sector fetch failed after 3 attempts: \(error.localizedDescription)",
                            step: "ROADMGR"
                        )
                        await self.resetFetchState()
                        return
                    } else {
                        // Silent retry after a short delay
                        try? await Task.sleep(for: .seconds(2))
                        attempt += 1
                    }
                }
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
    
    // MARK: - Orthogonal Snapping Math
    
    /// Takes a raw acoustic coordinate and snaps it to the nearest cached road segment.
    /// Returns the original coordinate if no roads are nearby.
    func snapToNearestRoad(rawCoordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !cachedRoadSegments.isEmpty else { return rawCoordinate }
        
        let rawPoint = MKMapPoint(rawCoordinate)
        var closestPoint: MKMapPoint? = nil
        var minDistance: CLLocationDistance = Double.infinity
        
        // Iterate through every cached road
        for road in cachedRoadSegments {
            // A road is a series of connected points. We must check every line segment.
            for i in 0..<(road.count - 1) {
                let p1 = MKMapPoint(road[i])
                let p2 = MKMapPoint(road[i + 1])
                
                // Calculate the closest point on this specific line segment
                let snapped = closestPointOnSegment(point: rawPoint, segmentStart: p1, segmentEnd: p2)
                let distance = rawPoint.distance(to: snapped)
                
                if distance < minDistance {
                    minDistance = distance
                    closestPoint = snapped
                }
            }
        }
        
        // If we found a road within a reasonable threshold (e.g., 150 meters), snap to it.
        // Otherwise, trust the raw acoustic data.
        if let bestSnap = closestPoint, minDistance < 150.0 {
            return bestSnap.coordinate
        }
        
        return rawCoordinate
    }
    
    /// Calculates the orthogonal projection of a point onto a line segment
    private func closestPointOnSegment(point: MKMapPoint, segmentStart: MKMapPoint, segmentEnd: MKMapPoint) -> MKMapPoint {
        let dx = segmentEnd.x - segmentStart.x
        let dy = segmentEnd.y - segmentStart.y
        let lengthSquared = dx * dx + dy * dy
        
        // If the segment is just a single point
        if lengthSquared == 0 { return segmentStart }
        
        // Calculate the projection scalar (t)
        let t = max(0, min(1, ((point.x - segmentStart.x) * dx + (point.y - segmentStart.y) * dy) / lengthSquared))
        
        // Calculate the actual projected point
        let projX = segmentStart.x + t * dx
        let projY = segmentStart.y + t * dy
        
        return MKMapPoint(x: projX, y: projY)
    }
}
