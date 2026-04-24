import Foundation
import CoreLocation
import Observation
import SwiftUI

// A smoothed, persistent vehicle traveling on the map
@Observable
class TrackedTarget: Identifiable {
    
    // THE FIX: Using native UUID to exactly match your SoundEvent sessionID
    let id: UUID
    var currentLabel: String
    
    // The smoothed UI coordinate
    var smoothedCoordinate: CLLocationCoordinate2D
    
    // Physics variables for the filter
    private(set) var lastUpdateTime: Date
    private var estimatedHeading: Double = 0.0
    private var estimatedSpeedMPS: Double = 0.0 // Meters per second
    
    // The complementary filter factor (0.0 to 1.0)
    // Higher = heavily favors smooth predicting, Lower = favors raw jumpy GPS
    private let smoothingFactor = 0.85

    // Put this right below your smoothingFactor variable
    private var glideTimer: Timer?
    
    // Add this function anywhere inside the class
    @MainActor
    private func startDeadReckoning() {
        glideTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self, self.estimatedSpeedMPS > 0 else { return }
            let coastedCoordinate = self.projectCoordinate(from: self.smoothedCoordinate, heading: self.estimatedHeading, distanceMeters: self.estimatedSpeedMPS * 0.03)
            self.smoothedCoordinate = coastedCoordinate
        }
    }
    
    init(initialEvent: SoundEvent) {
        // Matches the struct perfectly now
        self.id = initialEvent.sessionID
        self.currentLabel = initialEvent.threatLabel
        self.smoothedCoordinate = CLLocationCoordinate2D(
            latitude: initialEvent.latitude ?? 0.0,
            longitude: initialEvent.longitude ?? 0.0
        )
        self.lastUpdateTime = initialEvent.timestamp
        
        // Add this to your init(initialEvent:)
        startDeadReckoning()
    }
    
    func update(with rawEvent: SoundEvent) {
        guard let rawLat = rawEvent.latitude, let rawLon = rawEvent.longitude else { return }
        
        let now = rawEvent.timestamp
        let deltaTime = now.timeIntervalSince(lastUpdateTime)
        guard deltaTime > 0 else { return }
        
        let rawCoordinate = CLLocationCoordinate2D(latitude: rawLat, longitude: rawLon)
        
        // 1. If this is the first update, just calculate the initial heading
        if estimatedSpeedMPS == 0.0 {
            self.estimatedHeading = calculateBearing(from: smoothedCoordinate, to: rawCoordinate)
            let distance = calculateDistance(from: smoothedCoordinate, to: rawCoordinate)
            self.estimatedSpeedMPS = min(distance / deltaTime, 35.0) // Cap at ~80mph
        }
        
        // 2. Predict where the car SHOULD be based on its last known speed and heading
        let predictedCoordinate = projectCoordinate(from: smoothedCoordinate, heading: estimatedHeading, distanceMeters: estimatedSpeedMPS * deltaTime)
        
        // 3. THE COMPLEMENTARY FILTER
        // Blend the smooth prediction with the raw sensor data
        let blendedLat = (predictedCoordinate.latitude * smoothingFactor) + (rawCoordinate.latitude * (1.0 - smoothingFactor))
        let blendedLon = (predictedCoordinate.longitude * smoothingFactor) + (rawCoordinate.longitude * (1.0 - smoothingFactor))
        
        let newSmoothedCoordinate = CLLocationCoordinate2D(latitude: blendedLat, longitude: blendedLon)
        
        // 4. Update the physics engine for the next frame
        self.estimatedHeading = calculateBearing(from: smoothedCoordinate, to: newSmoothedCoordinate)
        let distanceMoved = calculateDistance(from: smoothedCoordinate, to: newSmoothedCoordinate)
        self.estimatedSpeedMPS = min(distanceMoved / deltaTime, 35.0)
        
        // Assign it directly! (The background glideTimer is handling the animation now)
        self.smoothedCoordinate = newSmoothedCoordinate
        
        self.currentLabel = rawEvent.threatLabel // Allow the label to update if the ML gets a better read
        self.lastUpdateTime = now
    }
    
    // MARK: - Geo Math Helpers
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return loc1.distance(from: loc2)
    }
    
    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        return (radiansBearing * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    
    private func projectCoordinate(from: CLLocationCoordinate2D, heading: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6378137.0
        let angularDist = distanceMeters / earthRadius
        let bearingRad = heading * .pi / 180.0
        
        let originLatRad = from.latitude * .pi / 180.0
        let originLonRad = from.longitude * .pi / 180.0
        
        let destLatRad = asin(sin(originLatRad) * cos(angularDist) + cos(originLatRad) * sin(angularDist) * cos(bearingRad))
        let destLonRad = originLonRad + atan2(sin(bearingRad) * sin(angularDist) * cos(originLatRad), cos(angularDist) - sin(originLatRad) * sin(destLatRad))
        
        return CLLocationCoordinate2D(latitude: destLatRad * 180.0 / .pi, longitude: destLonRad * 180.0 / .pi)
    }
}
