import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @Environment(AcousticCoordinator.self) private var coordinator
    
    static let CAMERA_DISTANCE: Double = 400
    
    var events: [SoundEvent]
    var userLocation: CLLocation?
    var userHeading: Double
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isTrackingUser: Bool = true
    
    var body: some View {
        Map(position: $cameraPosition, bounds: MapCameraBounds(minimumDistance: 100, maximumDistance: 800), interactionModes: .all) {
            UserAnnotation()
            
            if let route = coordinator.simulatedRoute {
                MapPolyline(route)
                    .stroke(.red.opacity(0.2), lineWidth: 3)
            }
            
            if let location = userLocation {
                let center = location.coordinate
                
                // Tactical Horizons
                MapCircle(center: center, radius: 304.8).foregroundStyle(.red.opacity(0.12)).stroke(.red.opacity(0.4), lineWidth: 1)
                MapCircle(center: center, radius: 152.4).foregroundStyle(.yellow.opacity(0.10)).stroke(.yellow.opacity(0.5), lineWidth: 1.5)
                MapCircle(center: center, radius: 9.144).foregroundStyle(.green.opacity(0.15)).stroke(.green.opacity(0.8), lineWidth: 2.5)
                
                // 1. Draw the "noisy" dots first at low opacity
                ForEach(events) { event in
                    Annotation("", coordinate: getProjectedCoordinate(for: event, center: center)) {
                        Circle()
                            .fill(SoundProfile.classify(event.threatLabel).color.opacity(0.15))
                            .frame(width: 6, height: 6)
                    }
                }
                
                // 2. Draw the "Smoothed Targets" LAST so they are always on top
                ForEach(coordinator.mapManager.visibleTargets) { target in
                    Annotation("", coordinate: target.smoothedCoordinate) {
                        let profile = SoundProfile.classify(target.currentLabel)
                        
                        ZStack {
                            if profile.isEmergency {
                                Image(systemName: profile.icon)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(profile.color)
                                    .shadow(color: profile.color, radius: 10)
                            } else {
                                Image(systemName: profile.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(profile.color)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(radius: 3)
                            }
                        }
                    }
                }
        
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .simultaneousGesture(DragGesture().onChanged { _ in isTrackingUser = false })
        .simultaneousGesture(MagnifyGesture().onChanged { _ in isTrackingUser = false })
        .onChange(of: userLocation) { _, _ in updateCamera() }
        .onChange(of: userHeading) { _, _ in updateCamera() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SnapToUser"))) { _ in
            isTrackingUser = true
            updateCamera(animated: true)
        }
    }
    
    private func updateCamera(animated: Bool = false) {
        guard isTrackingUser, let loc = userLocation else { return }
        let cam = MapCamera(centerCoordinate: loc.coordinate, distance: MapView.CAMERA_DISTANCE, heading: userHeading)
        if animated {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                cameraPosition = .camera(cam)
            }
        } else {
            cameraPosition = .camera(cam)
        }
    }
    
    private func getProjectedCoordinate(for event: SoundEvent, center: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if let lat = event.latitude, let lon = event.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            // Fallback for simulation or manual bells
            let distanceInMeters = Double(event.distance) * 304.8
            let geographicBearing = (userHeading + Double(event.bearing)).truncatingRemainder(dividingBy: 360.0)
            return center.projected(by: distanceInMeters, bearingDegrees: geographicBearing)
        }
    }
}
