//
//  TrackedTarget.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/13/26.
//  Reviewed and refined by Grok on 5/2/2026
//

import Foundation
import CoreLocation
import Observation
import SwiftUI

/// A smoothed, persistent vehicle/target shown on the map with dead-reckoning.
/// Uses complementary filtering + coasting when new data is sparse.
@Observable
@MainActor
class TrackedTarget: Identifiable {
    
    // MARK: - Public Identity & State
    
    let id: UUID
    var currentLabel: String
    
    var smoothedCoordinate: CLLocationCoordinate2D
    var smoothedDistance: Double = 0.0
    
    // MARK: - Physics State
    
    private(set) var lastUpdateTime: Date
    private var estimatedHeading: Double = 0.0
    private var estimatedSpeedMPS: Double = 0.0
    
    private let smoothingFactor = 0.85
    private let distanceSmoothingFactor = 0.70
    
    // MARK: - Dead Reckoning Timer
    
    private var glideTimer: Timer?
    
    // MARK: - Initialization
    
    init(initialEvent: SoundEvent) {
        self.id = initialEvent.sessionID
        self.currentLabel = initialEvent.threatLabel
        self.smoothedCoordinate = CLLocationCoordinate2D(
            latitude: initialEvent.latitude ?? 0.0,
            longitude: initialEvent.longitude ?? 0.0
        )
        self.smoothedDistance = initialEvent.distance
        self.lastUpdateTime = initialEvent.timestamp
        
        startDeadReckoning()
    }
    
    @MainActor
    deinit {
        glideTimer?.invalidate()
    }
    
    // MARK: - Dead Reckoning (Coasting)
    @MainActor
    private func startDeadReckoning() {
        glideTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Now safely inside a strong reference + @MainActor context
            Task { @MainActor in
                guard self.estimatedSpeedMPS > 0 else { return }
                
                let coastedCoordinate = self.projectCoordinate(
                    from: self.smoothedCoordinate,
                    heading: self.estimatedHeading,
                    distanceMeters: self.estimatedSpeedMPS * 0.03
                )
                
                self.smoothedCoordinate = coastedCoordinate
            }
        }
    }
    
    // MARK: - Main Update
    
    func update(with rawEvent: SoundEvent) {
        guard let rawLat = rawEvent.latitude, let rawLon = rawEvent.longitude else { return }
        
        let now = rawEvent.timestamp
        let deltaTime = now.timeIntervalSince(lastUpdateTime)
        guard deltaTime > 0 else { return }
        
        let rawCoordinate = CLLocationCoordinate2D(latitude: rawLat, longitude: rawLon)
        
        // Smooth distance
        let rawDistance = rawEvent.distance
        smoothedDistance = (smoothedDistance * distanceSmoothingFactor) + (rawDistance * (1.0 - distanceSmoothingFactor))
        
        if estimatedSpeedMPS == 0.0 {
            self.estimatedHeading = calculateBearing(from: smoothedCoordinate, to: rawCoordinate)
            let distance = calculateDistance(from: smoothedCoordinate, to: rawCoordinate)
            self.estimatedSpeedMPS = min(distance / deltaTime, 35.0)
        }
        
        let predictedCoordinate = projectCoordinate(
            from: smoothedCoordinate,
            heading: estimatedHeading,
            distanceMeters: estimatedSpeedMPS * deltaTime
        )
        
        let blendedLat = (predictedCoordinate.latitude * smoothingFactor) + (rawCoordinate.latitude * (1.0 - smoothingFactor))
        let blendedLon = (predictedCoordinate.longitude * smoothingFactor) + (rawCoordinate.longitude * (1.0 - smoothingFactor))
        
        let newSmoothedCoordinate = CLLocationCoordinate2D(latitude: blendedLat, longitude: blendedLon)
        
        self.estimatedHeading = calculateBearing(from: smoothedCoordinate, to: newSmoothedCoordinate)
        let distanceMoved = calculateDistance(from: smoothedCoordinate, to: newSmoothedCoordinate)
        self.estimatedSpeedMPS = min(distanceMoved / deltaTime, 35.0)
        
        self.smoothedCoordinate = newSmoothedCoordinate
        self.currentLabel = rawEvent.threatLabel
        self.lastUpdateTime = now
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
        let earthRadius = 6378137.0
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
}
