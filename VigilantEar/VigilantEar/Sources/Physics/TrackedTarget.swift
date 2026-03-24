import Foundation
import CoreLocation
import Observation
import SwiftUI

@Observable
class TrackedTarget: Identifiable {
    
    let id: UUID
    var currentLabel: String
    var profile: SoundProfile
    var smoothedCoordinate: CLLocationCoordinate2D
    var smoothedDistance: Double = 0.0
    let iconTintColor: Color
    var activeEvent: SoundEvent?
    
    private(set) var lastUpdateTime: Date
    private var estimatedHeading: Double = 0.0
    private var estimatedSpeedMPS: Double = 0.0
    private var glideTimer: Timer?
    
    init(initialEvent: SoundEvent) {
        self.id = initialEvent.sessionID
        self.currentLabel = initialEvent.threatLabel
        self.profile = initialEvent.profile
        self.smoothedCoordinate = CLLocationCoordinate2D(
            latitude: initialEvent.latitude ?? 0.0,
            longitude: initialEvent.longitude ?? 0.0
        )
        self.smoothedDistance = initialEvent.distance * 1000.0
        self.lastUpdateTime = initialEvent.timestamp
        self.activeEvent = initialEvent
        self.iconTintColor = AppGlobals.VehicleColors.iconTint(for: initialEvent.sessionID)
        self.startDeadReckoning()
    }
    
    deinit {
        glideTimer?.invalidate()
    }
    
    func update(with rawEvent: SoundEvent) {
        guard let rawLat = rawEvent.latitude, let rawLon = rawEvent.longitude else { return }
        
        let now = rawEvent.timestamp
        let deltaTime = now.timeIntervalSince(lastUpdateTime)
        guard deltaTime > 0 else { return }
        
        let rawCoordinate = CLLocationCoordinate2D(latitude: rawLat, longitude: rawLon)
        
        let rawDistance = rawEvent.distance
        smoothedDistance = (smoothedDistance * AppGlobals.Tracking.distanceSmoothingFactor) + (rawDistance * (1.0 - AppGlobals.Tracking.distanceSmoothingFactor))
        
        if estimatedSpeedMPS == 0.0 {
            self.estimatedHeading = calculateBearing(from: smoothedCoordinate, to: rawCoordinate)
            let distance = calculateDistance(from: smoothedCoordinate, to: rawCoordinate)
            self.estimatedSpeedMPS = min(distance / deltaTime, AppGlobals.Tracking.maxEstimatedSpeedMPS)
        }
        
        let predictedCoordinate = projectCoordinate(
            from: smoothedCoordinate,
            heading: estimatedHeading,
            distanceMeters: estimatedSpeedMPS * deltaTime
        )
        
        let blendedLat = (predictedCoordinate.latitude * AppGlobals.Tracking.smoothingFactor) + (rawCoordinate.latitude * (1.0 - AppGlobals.Tracking.smoothingFactor))
        let blendedLon = (predictedCoordinate.longitude * AppGlobals.Tracking.smoothingFactor) + (rawCoordinate.longitude * (1.0 - AppGlobals.Tracking.smoothingFactor))
        
        let newSmoothedCoordinate = CLLocationCoordinate2D(latitude: blendedLat, longitude: blendedLon)
        
        self.estimatedHeading = calculateBearing(from: smoothedCoordinate, to: newSmoothedCoordinate)
        let distanceMoved = calculateDistance(from: smoothedCoordinate, to: newSmoothedCoordinate)
        self.estimatedSpeedMPS = min(distanceMoved / deltaTime, AppGlobals.Tracking.maxEstimatedSpeedMPS)
        
        self.smoothedCoordinate = newSmoothedCoordinate
        
        if self.currentLabel != rawEvent.threatLabel {
            self.currentLabel = rawEvent.threatLabel
            self.profile = rawEvent.profile   // still cached
        }
        
        self.lastUpdateTime = now
        self.activeEvent = rawEvent
    }
    
    // MARK: - Helper Functions (unchanged)
    
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
        let earthRadius = AppGlobals.Geo.earthRadiusMeters
        let angularDist = distanceMeters / earthRadius
        let bearingRad = heading * .pi / 180.0
        let originLatRad = from.latitude * .pi / 180.0
        let originLonRad = from.longitude * .pi / 180.0
        
        let destLatRad = asin(sin(originLatRad) * cos(angularDist) + cos(originLatRad) * sin(angularDist) * cos(bearingRad))
        let destLonRad = originLonRad + atan2(
            sin(bearingRad) * sin(angularDist) * cos(originLatRad),
            cos(angularDist) - sin(originLatRad) * sin(destLatRad)
        )
        
        return CLLocationCoordinate2D(
            latitude: destLatRad * 180.0 / .pi,
            longitude: destLonRad * 180.0 / .pi
        )
    }
    
    private func startDeadReckoning() {
        glideTimer = Timer.scheduledTimer(withTimeInterval: AppGlobals.Rendering.targetGlideInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.estimatedSpeedMPS > 0 else { return }
                // Reduced frequency from 33Hz to 10Hz to prevent main thread overload
                let coastedCoordinate = self.projectCoordinate(
                    from: self.smoothedCoordinate,
                    heading: self.estimatedHeading,
                    distanceMeters: self.estimatedSpeedMPS * AppGlobals.Rendering.targetGlideDistanceMultiplier
                )
                self.smoothedCoordinate = coastedCoordinate
            }
        }
    }
}
