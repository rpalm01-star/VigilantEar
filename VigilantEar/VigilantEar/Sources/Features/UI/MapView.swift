import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    var events: [SoundEvent]
    var userLocation: CLLocation?
    var userHeading: Double
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    var body: some View {
        Map(position: $cameraPosition) {
            
            // 1. User Location
            UserAnnotation()
            
            // 2. The Tactical Horizons
            if let location = userLocation {
                let center = location.coordinate
                
                // Outer Ring (Bleeds off the screen for a cool radar effect)
                MapCircle(center: center, radius: 304.8)
                    .foregroundStyle(.red.opacity(0.05))
                    .stroke(.red.opacity(0.3), lineWidth: 1)
                
                // Middle Tracking Ring
                MapCircle(center: center, radius: 152.4)
                    .foregroundStyle(.yellow.opacity(0.08))
                    .stroke(.yellow.opacity(0.5), lineWidth: 1.5)
                
                // Inner 30ft Perimeter
                MapCircle(center: center, radius: 9.144)
                    .foregroundStyle(.green.opacity(0.15))
                    .stroke(.green.opacity(0.8), lineWidth: 2.5)
                
                // 3. The Threat Dots
                ForEach(events) { event in
                    let distanceInMeters = Double(event.distance) * 9.144
                    let absoluteBearing = userHeading + Double(event.bearing)
                    let projectedCoord = center.projected(by: distanceInMeters, bearingDegrees: absoluteBearing)
                    
                    // Restored: Emergency color logic
                    let dotColor = event.isEmergency ? Color.red : Color.cyan
                    
                    // Fixed: Pass an empty string to remove the messy map text
                    Annotation("", coordinate: projectedCoord) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 16, height: 16)
                            .shadow(color: dotColor, radius: 8)
                            .scaleEffect(CGFloat(max(0.5, event.energy))) // Pulses based on volume
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .onChange(of: userHeading) { _, newHeading in
            updateCamera(location: userLocation, heading: newHeading)
        }
        .onChange(of: userLocation) { _, newLocation in
            updateCamera(location: newLocation, heading: userHeading)
        }
        .onAppear {
            updateCamera(location: userLocation, heading: userHeading)
        }
    }
    
    private func updateCamera(location: CLLocation?, heading: Double) {
        guard let loc = location else { return }
        
        // Fixed: Dropped altitude from 1200 to 400 for a tight, tactical zoom
        let camera = MapCamera(
            centerCoordinate: loc.coordinate,
            distance: 400,
            heading: heading,
            pitch: 0
        )
        cameraPosition = .camera(camera)
    }
}

// MARK: - Local Extension
extension CLLocationCoordinate2D {
    func projected(by distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let earthRadius: Double = 6378137.0 // in meters
        
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
