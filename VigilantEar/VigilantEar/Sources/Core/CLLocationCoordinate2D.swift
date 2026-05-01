//
//  CLLocationCoordinate2D.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/23/26.
//


import SwiftUI
import MapKit
import CoreLocation

extension CLLocationCoordinate2D {
    func projected(by distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let earthRadius: Double = 6378137.0
        let lat1 = self.latitude * .pi / 180.0
        let lon1 = self.longitude * .pi / 180.0
        let bearingRad = bearingDegrees * .pi / 180.0
        let lat2 = asin(sin(lat1) * cos(distanceMeters / earthRadius) +
                        cos(lat1) * sin(distanceMeters / earthRadius) * cos(bearingRad))
        let lon2 = lon1 + atan2(sin(bearingRad) * sin(distanceMeters / earthRadius) * cos(lat1),
                                cos(distanceMeters / earthRadius) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180.0 / .pi, longitude: lon2 * 180.0 / .pi)
    }
}
