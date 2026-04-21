import SwiftUI
import MapKit
import CoreLocation

// --- EXTENSION MUST BE AT TOP LEVEL ---
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

struct MapView: View {
    @Environment(AcousticCoordinator.self) private var coordinator
    
    static let CAMERA_DISTANCE: Double = 400
    
    var events: [SoundEvent]
    var userLocation: CLLocation?
    var userHeading: Double
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isTrackingUser: Bool = true
    
    private var activeHeadIDs: Set<UUID> {
        var heads: [UUID: SoundEvent] = [:]
        for event in events {
            if let existing = heads[event.sessionID] {
                if event.timestamp > existing.timestamp { heads[event.sessionID] = event }
            } else { heads[event.sessionID] = event }
        }
        return Set(heads.values.filter { $0.age < 4.0 }.map { $0.id })
    }
    
    var body: some View {
        Map(position: $cameraPosition, bounds: MapCameraBounds(minimumDistance: 100, maximumDistance: 800), interactionModes: .all) {
            UserAnnotation()
            
            // DRAW THE PATH: This stays pinned to the ground during rotation
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
                
                // --- REAL-WORLD BREADCRUMBS (Traffic Trails) ---
                // Group all events by their session ID
                let groupedEvents = Dictionary(grouping: events, by: \.sessionID)
                
                // Only draw trails for threats that are currently active
                ForEach(Array(activeHeadIDs), id: \.self) { sessionID in
                    if let trackEvents = groupedEvents[sessionID], trackEvents.count > 1 {
                        
                        // Sort them chronologically so the line draws from oldest to newest
                        let sortedTrack = trackEvents.sorted { $0.timestamp < $1.timestamp }
                        
                        // Map the events to actual MapKit coordinates using our helper function
                        let coords = sortedTrack.map { getProjectedCoordinate(for: $0, center: center) }
                        
                        // Grab the profile color from the most recent event in the track
                        let profile = SoundProfile.classify(sortedTrack.last!.threatLabel)
                        
                        // Draw the fading trail
                        MapPolyline(coordinates: coords)
                            .stroke(profile.color.opacity(0.4), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
                
                ForEach(events, id: \.id) { event in
                    // THE FIX: Call the helper function directly to keep the MapContentBuilder happy
                    Annotation("", coordinate: getProjectedCoordinate(for: event, center: center)) {
                        
                        // Local variables are fine INSIDE the Annotation's ViewBuilder!
                        let profile = SoundProfile.classify(event.threatLabel)
                        let isHeadOfTrack = activeHeadIDs.contains(event.id)
                        
                        ZStack {
                            if isHeadOfTrack, let rate = event.dopplerRate, abs(Double(rate)) > 1.0 {
                                
                                let iconOffset: Double = -45.0
                                
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(profile.color.opacity(0.8))
                                    .offset(y: -18)
                                    .scaleEffect(x: 1.0, y: 1.0 + CGFloat(abs(Double(rate)) / 10.0), anchor: .bottom)
                                    .rotationEffect(.degrees(event.bearing + (event.isApproaching ? 180.0 : 0.0) + iconOffset))
                            }
                            
                            if isHeadOfTrack && profile.isEmergency {
                                Image(systemName: profile.icon)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(profile.color)
                                    .shadow(color: profile.color, radius: 10)
                                    .opacity(event.opacity)
                            } else {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(profile.color)
                                    .opacity(event.opacity)
                                    .scaleEffect(CGFloat(max(0.6, event.visualScale)) * CGFloat(max(0.3, event.opacity)))
                                    .shadow(color: profile.color, radius: CGFloat(event.energy) * 15)
                            }
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        // --- Listen for physical screen touches instead of programmatic camera changes ---
        .simultaneousGesture(DragGesture().onChanged { _ in
            if isTrackingUser { isTrackingUser = false }
        })
        .simultaneousGesture(MagnifyGesture().onChanged { _ in
            if isTrackingUser { isTrackingUser = false }
        })
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
        // Use absolute GPS coordinates if we have them so the dot stays glued to the street!
        if let lat = event.latitude, let lon = event.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            let distanceInMeters = Double(event.distance) * 304.8
            let geographicBearing = (userHeading + Double(event.bearing)).truncatingRemainder(dividingBy: 360.0)
            return center.projected(by: distanceInMeters, bearingDegrees: geographicBearing)
        }
    }
}
