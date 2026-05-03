import Foundation
import CoreLocation
import MapKit

@MainActor
struct ThreatSimulator {
    
    // Internal helper to keep simulation state thread-safe for Swift 6
    private class SimulationState {
        var step = 0
        var previousDistance: Double = 9999.0
        var isApproaching = true
        var intersectionStopTicks = 50
    }
    
    static func runFireTruckDriveBy(
        location: CLLocation?,
        heading: Double,
        coordinator: AcousticCoordinator
    ) {
        guard let location = location else { return }
        
        coordinator.simulatedRoute = nil
        
        Task { @MainActor in
            let startCoord = location.coordinate.projected(by: 243.8, bearingDegrees: heading + 90)
            let endCoord = location.coordinate.projected(by: 243.8, bearingDegrees: heading - 90)
            
            let request = MKDirections.Request()
            
            let sourceLocation = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
            let destinationLocation = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
            
            // Fixed: Explicitly passing nil for address to satisfy the iOS 26 compiler
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
                
                coordinator.simulatedRoute = route
                var pathCoordinates = route.polyline.denselySampled(spacingMeters: 2.0)
                
                pathCoordinates = pathCoordinates.filter { coord in
                    let point = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    return location.distance(from: point) <= 152.4
                }
                
                guard !pathCoordinates.isEmpty else {
                    AppGlobals.doLog(message: "⚠️ " + AppGlobals.simulatedFireTruck.capitalized + ": Range truncation Resulted in zero points.", step: "FIRESIM")
                    coordinator.simulatedRoute = nil
                    return
                }
                
                let state = SimulationState()
                let threatSessionID = UUID()
                let intersectionIndex = pathCoordinates.count / 2
                
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    guard state.step < pathCoordinates.count else {
                        timer.invalidate()
                        coordinator.simulatedRoute = nil
                        return
                    }
                    
                    let currentCoord = pathCoordinates[state.step]
                    let truckLocation = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
                    let distanceInMeters = location.distance(from: truckLocation)
                    let distanceInFeet = distanceInMeters * 3.28084
                    
                    if distanceInFeet > state.previousDistance { state.isApproaching = false }
                    state.previousDistance = distanceInFeet
                    
                    let absoluteBearing = getBearingBetween(location.coordinate, currentCoord)
                    var relativeBearing = absoluteBearing - heading
                    if relativeBearing > 180 { relativeBearing -= 360 }
                    if relativeBearing < -180 { relativeBearing += 360 }
                    
                    let normalizedDistance = distanceInFeet / 1000.0
                    let simulatedEnergy = max(0.05, 1.0 - (distanceInFeet / 1000.0))
                    let simulatedConfidence = max(0.3, 1.0 - (distanceInFeet / 1000.0))
                    
                    let isCurrentlyStopped = (state.step == intersectionIndex && state.intersectionStopTicks > 0)
                    let activeDoppler = isCurrentlyStopped ? 0.0 : (state.isApproaching ? 15.6 : -15.6)
                    
                    let newEvent = SoundEvent(
                        sessionID: threatSessionID,
                        timestamp: Date(),
                        threatLabel: AppGlobals.simulatedFireTruck,
                        confidence: simulatedConfidence,
                        bearing: relativeBearing,
                        distance: normalizedDistance,
                        energy: Float(simulatedEnergy),
                        dopplerRate: Float(activeDoppler),
                        isApproaching: state.isApproaching,
                        latitude: truckLocation.coordinate.latitude,
                        longitude: truckLocation.coordinate.longitude,
                        isRevealed: true,
                        songLabel: nil
                    )
                    
                    coordinator.addEvent(newEvent)
                    
                    if (state.step == 1) {
                        let profile = SoundProfile.classify(AppGlobals.simulatedFireTruck)
                        if (profile.hapticCount > 0) {
                            HapticManager.shared.trigger(count: profile.hapticCount, sessionID: newEvent.sessionID)
                        }
                    }
                    
                    if isCurrentlyStopped {
                        state.intersectionStopTicks -= 1
                    } else {
                        state.step += 1
                    }
                    
                    if state.step >= pathCoordinates.count {
                        timer.invalidate()
                        coordinator.simulatedRoute = nil
                    }
                }
            } catch {
                AppGlobals.doLog(message: "⚠️ Routing failed: \(error.localizedDescription)", step: "FIRESIM")
                coordinator.simulatedRoute = nil
            }
        }
    }
    
    private nonisolated static func getBearingBetween(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D) -> Double {
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
        let count = self.pointCount
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
        
        // Fixed: Swift 6 pointer extraction
        _ = coords.withUnsafeMutableBufferPointer { buffer in
            self.getCoordinates(buffer.baseAddress!, range: NSRange(location: 0, length: count))
        }
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
