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
                let hasEmergencyInside500ft = events.contains { event in
                    event.isEmergency && (event.distance * 1000.0) <= 500.0
                }
                
                // 1000ft red circle
                MapCircle(center: center, radius: 304.8)
                    .foregroundStyle(.red.opacity(0.06))
                    .stroke(.red.opacity(0.4), lineWidth: 1)
                
                // Base 500ft yellow circle (always visible)
                MapCircle(center: center, radius: 152.4)
                    .foregroundStyle(.yellow.opacity(0.08))
                    .stroke(.yellow, lineWidth: 1.5)
                
                // Traveling red ring (expands from center → rim → back)
                if hasEmergencyInside500ft {
                    let t = Date().timeIntervalSince1970 * 1.4
                    let progress = (sin(t) + 1) / 2                    // 0 → 1 → 0
                    
                    let ringRadius = 15 + (progress * 137)             // starts small, expands to ~152m
                    
                    // Opacity: low near center, higher at edge, then reverses on the way back
                    let ringOpacity = 0.02 + (progress * 0.12)
                    
                    MapCircle(center: center, radius: ringRadius)
                        .foregroundStyle(.red.opacity(ringOpacity))
                }
                
                // 30ft green circle
                MapCircle(center: center, radius: 9.144)
                    .foregroundStyle(.green.opacity(0.15))
                    .stroke(.green.opacity(0.8), lineWidth: 2.5)
                
                // 2. Draw the "Smoothed Targets" LAST so they are always on top
                ForEach(coordinator.mapManager.visibleTargets) { target in
                    Annotation("", coordinate: target.smoothedCoordinate) {
                        let profile = SoundProfile.classify(target.currentLabel)
                        
                        // Grab the latest raw event for this target to read the live doppler
                        let activeEvent = events.last(where: { $0.sessionID == target.id })
                        
                        ZStack {
                            // The Main Icon
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
                            
                            // --- THE ORBITAL DOPPLER CARET ---
                            if let event = activeEvent, let rate = event.dopplerRate, abs(rate) > 0.1 {
                                // If approaching, point AT the user (bearing + 180). If receding, point AWAY (bearing).
                                let pointingAngle = event.isApproaching ? (event.bearing + 180) : event.bearing
                                
                                // THE FIX: Swapped triangle.fill for the sleek chevron.up caret
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 14, weight: .black)) // Bumped size from 10 to 14 for readability
                                    .foregroundColor(event.isApproaching ? .red : .green)
                                    .shadow(color: .black.opacity(0.8), radius: 2)
                                    .offset(y: profile.isEmergency ? -36 : -32)
                                    .rotationEffect(.degrees(pointingAngle))
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
            let distanceInMeters = Double(event.distance) * 304.8
            let geographicBearing = (userHeading + Double(event.bearing)).truncatingRemainder(dividingBy: 360.0)
            return center.projected(by: distanceInMeters, bearingDegrees: geographicBearing)
        }
    }
}
