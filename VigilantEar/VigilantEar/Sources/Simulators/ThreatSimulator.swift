import Foundation
import CoreLocation
import MapKit

@MainActor
struct ThreatSimulator {
    
    // 🚨 1. Track the active task so we can kill it if the user restarts the sim
    private static var activeSimulationTask: Task<Void, Never>?
        
    static func runFireTruckDriveBy(
        location: CLLocation?,
        heading: Double,
        coordinator: AcousticCoordinator
    ) {
        guard let location = location else { return }
        
        // 2. Kill any ghost simulators and clear old routes
        activeSimulationTask?.cancel()
        coordinator.simulatedRoute = nil
        let profile = SoundProfile.classify(AppGlobals.simulatedFireTruck)
        
        activeSimulationTask = Task {
            // Cast a net (800ft / 243m) to find road-legal coordinates
            let startCoord = location.coordinate.projected(by: 243.8, bearingDegrees: heading + 90)
            let endCoord = location.coordinate.projected(by: 243.8, bearingDegrees: heading - 90)
            
            let request = MKDirections.Request()
            let sourceLocation = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
            let destinationLocation = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
            
            request.source = MKMapItem(location: sourceLocation, address: nil)
            request.destination = MKMapItem(location: destinationLocation, address: nil)
            request.transportType = .automobile
            
            let directions = MKDirections(request: request)
            
            do {
                let response = try await directions.calculate()
                guard let route = response.routes.first else {
                    AppGlobals.doLog(message: "⚠️ " + AppGlobals.simulatedFireTruck.capitalized + ": No routes found.", step: "FIRESIM")
                    return
                }
                
                // Store the route so MapView draws the geographic line
                coordinator.simulatedRoute = route
                
                // Densely sample the line for smooth movement
                var pathCoordinates = route.polyline.denselySampled(spacingMeters: 2.0)
                
                // Truncate: Only keep points within the 500ft (152.4m) Yellow Circle
                pathCoordinates = pathCoordinates.filter { coord in
                    let point = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    return location.distance(from: point) <= 152.4
                }
                
                guard !pathCoordinates.isEmpty else {
                    AppGlobals.doLog(message: "⚠️ " + AppGlobals.simulatedFireTruck.capitalized + ": Range truncation resulted in zero points.", step: "FIRESIM")
                    coordinator.simulatedRoute = nil
                    return
                }
                
                // SIMULATION STATE
                var step = 0
                var previousDistance: Double = 9999.0
                var isApproaching = true
                let threatSessionID = UUID()
                
                // 🚨 INTERSECTION STOP LOGIC
                let intersectionIndex = pathCoordinates.count / 2
                
                // 3. Update at 4Hz (0.25s) instead of 10Hz. TrackedTarget's dead-reckoning will smooth the visual gaps!
                let tickDuration = 1.0
                // 20 ticks * 0.25s = 5 seconds of idling
                var intersectionStopTicks = 10
                
                // 4. The Modern Async Loop (Automatically respects cancellation)
                while step < pathCoordinates.count && !Task.isCancelled {
                    
                    let currentCoord = pathCoordinates[step]
                    let truckLocation = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
                    let distanceInMeters = location.distance(from: truckLocation)
                    let distanceInFeet = distanceInMeters * 3.28084
                    
                    // Doppler & State
                    if distanceInFeet > previousDistance { isApproaching = false }
                    previousDistance = distanceInFeet
                    
                    // Relative Bearing Math
                    let absoluteBearing = getBearingBetween(location.coordinate, currentCoord)
                    var relativeBearing = absoluteBearing - heading
                    if relativeBearing > 180 { relativeBearing -= 360 }
                    if relativeBearing < -180 { relativeBearing += 360 }
                    
                    let normalizedDistance = distanceInFeet / 1000.0
                    let simulatedEnergy = max(0.05, 1.0 - (distanceInFeet / 1000.0))
                    let simulatedConfidence = max(0.3, 1.0 - (distanceInFeet / 1000.0))
                    
                    let isCurrentlyStopped = (step == intersectionIndex && intersectionStopTicks > 0)
                    let activeDoppler = isCurrentlyStopped ? 0.0 : (isApproaching ? 15.6 : -15.6)

                    let newEvent = SoundEvent(
                        sessionID: threatSessionID,
                        timestamp: Date(),
                        threatLabel: AppGlobals.simulatedFireTruck,
                        confidence: simulatedConfidence,
                        bearing: relativeBearing,
                        distance: normalizedDistance,
                        energy: Float(simulatedEnergy),
                        dopplerRate: Float(activeDoppler),
                        isApproaching: isApproaching,
                        latitude: truckLocation.coordinate.latitude,
                        longitude: truckLocation.coordinate.longitude,
                        isRevealed: true,
                        songLabel: nil,
                        profile: profile
                    )
                    
                    // Fire into the coordinator
                    coordinator.addEvent(newEvent)
                    
                    if step == 1 {
                        if profile.hapticCount > 0 {
                            AppGlobals.doLog(message: "🌀 " + AppGlobals.simulatedFireTruck.capitalized + ": Haptic request @start for : \(profile.hapticCount) pulses.", step: "FIRESIM")
                            HapticManager.shared.trigger(count: profile.hapticCount, sessionID: newEvent.sessionID)
                        }
                    }
                    
                    // MOVEMENT ADVANCEMENT
                    if isCurrentlyStopped {
                        intersectionStopTicks -= 1
                    } else {
                        step += 1
                    }
                    
                    // 5. Yield the thread safely
                    try? await Task.sleep(for: .seconds(tickDuration))
                }
                
                // Cleanup when the loop naturally finishes (or is cancelled)
                if !Task.isCancelled {
                    coordinator.simulatedRoute = nil
                }
                
            } catch {
                AppGlobals.doLog(message: "⚠️ Routing failed: \(error.localizedDescription)", step: "FIRESIM")
                coordinator.simulatedRoute = nil
            }
        }
    }
    
    private nonisolated static func getBearingBetween(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D) -> Double {
        // ... unchanged ...
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        return radiansBearing * 180 / .pi
    }
}

// MARK: - MapKit Extensions
extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
    
    func denselySampled(spacingMeters: Double = 1.0) -> [CLLocationCoordinate2D] {
        let coords = self.coordinates
        guard coords.count > 1 else { return coords }
        
        var dense: [CLLocationCoordinate2D] = []
        
        for i in 0..<(coords.count - 1) {
            let p1 = coords[i]
            let p2 = coords[i+1]
            let loc1 = CLLocation(latitude: p1.latitude, longitude: p1.longitude)
            let loc2 = CLLocation(latitude: p2.latitude, longitude: p2.longitude)
            let distance = loc1.distance(from: loc2)
            
            let steps = max(1, Int(ceil(distance / spacingMeters)))
            let latStep = (p2.latitude - p1.latitude) / Double(steps)
            let lonStep = (p2.longitude - p1.longitude) / Double(steps)
            
            for j in 0..<steps {
                dense.append(CLLocationCoordinate2D(
                    latitude: p1.latitude + latStep * Double(j),
                    longitude: p1.longitude + lonStep * Double(j)
                ))
            }
        }
        dense.append(coords.last!)
        return dense
    }
}
