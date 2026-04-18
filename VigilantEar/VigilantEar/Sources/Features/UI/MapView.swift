import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    
    static let CAMERA_DISTANCE = Double(400)
    
    var events: [SoundEvent]
    var userLocation: CLLocation?
    var userHeading: Double
    
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 32.7157, longitude: -117.1611), // It will auto-update to the user's GPS
            distance: MapView.CAMERA_DISTANCE
        )
    )
    
    var body: some View {
        // THE FIX: Tighten the bounds to 800 meters maximum!
        Map(
            position: $cameraPosition,
            bounds: MapCameraBounds(
                minimumDistance: 100, // Lets you zoom all the way in to your driveway
                maximumDistance: 800  // Hard brick-wall stop just outside the 1,000ft red ring
            )
        )
        {
        // 1. User Location (The blue dot)
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
                let distanceInMeters = Double(event.distance) * 304.8
                let absoluteBearing = userHeading + Double(event.bearing)
                let projectedCoord = center.projected(by: distanceInMeters, bearingDegrees: absoluteBearing)
                
                let dotColor = event.isEmergency ? Color.red : Color.cyan
                
                Annotation("", coordinate: projectedCoord) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 16, height: 16)
                    // THE FIX: Apply the exact fade math from the struct
                        .opacity(event.opacity)
                    // THE FIX: Multiply size by confidence (visualScale) and shrink as it fades!
                        .scaleEffect(CGFloat(event.visualScale) * CGFloat(max(0.3, event.opacity)))
                        .shadow(color: dotColor.opacity(0.8), radius: 8)
                }
            }
        }
        }
        // THE FIX: .excludingAll strips away every business, landmark, and transit icon!
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .mapControlVisibility(.hidden)
        .overlay(alignment: .bottomTrailing) {
            Button(action: {
                if let loc = userLocation {
                    // withAnimation gives it that buttery smooth "swoop" back to center
                    withAnimation(.easeInOut(duration: 1.0)) {
                        cameraPosition = .camera(
                            MapCamera(
                                centerCoordinate: loc.coordinate,
                                distance: 400, // Locks it right back into the Yellow Ring!
                                heading: userHeading,
                                pitch: 0
                            )
                        )
                    }
                }
            }) {
                Image(systemName: "location.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 50, height: 50)
                    .background(.thickMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 40) // Adjust this to sit nicely above your HUD!
        }
        .onAppear {
            if let loc = userLocation {
                let camera = MapCamera(
                    centerCoordinate: loc.coordinate,
                    distance: MapView.CAMERA_DISTANCE,
                    heading: userHeading,
                    pitch: 0
                )
                cameraPosition = .camera(camera)
            }
        }
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
