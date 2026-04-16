import Foundation
import CoreLocation
import MapKit

@MainActor
struct ThreatSimulator {
    
    static func runFireTruckDriveBy(
        location: CLLocation?,
        heading: Double,
        coordinator: AcousticCoordinator
    ) {
        guard let location = location else { return }
        
        Task {
            // 1. EXPANDED STAGE: 1,000 feet (304.8 meters) left and right!
            let startCoord = location.coordinate.projected(by: 304.8, bearingDegrees: heading - 90)
            let endCoord = location.coordinate.projected(by: 304.8, bearingDegrees: heading + 90)
            
            let request = MKDirections.Request()
            let startLoc = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
            let endLoc = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
            
            request.source = MKMapItem(location: startLoc, address: nil)
            request.destination = MKMapItem(location: endLoc, address: nil)
            request.transportType = .walking // Cheat code to ignore one-ways
            
            do {
                let directions = MKDirections(request: request)
                let response = try await directions.calculate()
                
                guard let route = response.routes.first else {
                    print("⚠️ Could not find a path.")
                    return
                }
                
                // 2. HIGHER SPEED: Sample every 2 meters.
                // At 0.1s ticks, this equals 20m/s (~45 mph) so you aren't waiting all day.
                let pathCoordinates = route.polyline.denselySampled(spacingMeters: 2.0)
                guard !pathCoordinates.isEmpty else { return }
                
                var step = 0
                let totalSteps = pathCoordinates.count
                var previousDistance: Double = 9999.0
                var isApproaching = true
                
                Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    let currentCoord = pathCoordinates[step]
                    
                    let truckLocation = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
                    let distanceInMeters = location.distance(from: truckLocation)
                    let distanceInFeet = distanceInMeters * 3.28084
                    
                    if distanceInFeet > previousDistance { isApproaching = false }
                    previousDistance = distanceInFeet
                    
                    let lat1 = location.coordinate.latitude * .pi / 180
                    let lon1 = location.coordinate.longitude * .pi / 180
                    let lat2 = currentCoord.latitude * .pi / 180
                    let lon2 = currentCoord.longitude * .pi / 180
                    
                    let dLon = lon2 - lon1
                    let y = sin(dLon) * cos(lat2)
                    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
                    let absoluteBearing = atan2(y, x) * 180 / .pi
                    
                    var relativeBearing = absoluteBearing - heading
                    if relativeBearing > 180 { relativeBearing -= 360 }
                    if relativeBearing < -180 { relativeBearing += 360 }
                    
                    // 3. THE FIX: Normalize using the new 1,000 foot radar scale
                    let normalizedDistance = distanceInFeet / 1000.0
                    
                    // Smooth volume fade starting from 1,000 feet out
                    let calculatedEnergy = max(0.05, 1.0 - (distanceInFeet / 1000.0))
                    
                    let event = SoundEvent(
                        threatLabel: "Fire_Truck",
                        bearing: relativeBearing,
                        distance: normalizedDistance,
                        energy: Float(calculatedEnergy),
                        dopplerRate: isApproaching ? 15.0 : -15.0,
                        isApproaching: isApproaching
                    )
                    
                    DispatchQueue.main.async {
                        coordinator.addEvent(event)
                    }
                    
                    step += 1
                    if step >= totalSteps { timer.invalidate() }
                }
                
            } catch {
                print("⚠️ Routing failed: \(error.localizedDescription)")
            }
        }
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
