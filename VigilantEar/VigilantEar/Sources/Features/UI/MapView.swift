import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    
    static let CAMERA_DISTANCE: Double = Double(400)
    
    var events: [SoundEvent]
    var userLocation: CLLocation?
    var userHeading: Double
    
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 32.7157, longitude: -117.1611),
            distance: MapView.CAMERA_DISTANCE
        )
    )
    
    @State private var isTrackingUser: Bool = true
    
    // THE FIX 1: Safely and accurately identifies the exact ID of the newest dot in every active track
    private var activeHeadIDs: Set<UUID> {
        var heads: [UUID: SoundEvent] = [:]
        for event in events {
            if let existing = heads[event.sessionID] {
                if event.timestamp > existing.timestamp {
                    heads[event.sessionID] = event
                }
            } else {
                heads[event.sessionID] = event
            }
        }
        // Only consider it a "Head" if it was heard in the last 4 seconds
        let freshHeads = heads.values.filter { $0.age < 4.0 }
        return Set(freshHeads.map { $0.id })
    }
    
    var body: some View {
        Map(
            position: $cameraPosition,
            bounds: MapCameraBounds(
                minimumDistance: 100,
                maximumDistance: 800
            )
        )
        {
        UserAnnotation()
        
        if let location = userLocation {
            let center = location.coordinate
            
            MapCircle(center: center, radius: 304.8)
                .foregroundStyle(.red.opacity(0.05))
                .stroke(.red.opacity(0.3), lineWidth: 1)
            
            MapCircle(center: center, radius: 152.4)
                .foregroundStyle(.yellow.opacity(0.08))
                .stroke(.yellow.opacity(0.5), lineWidth: 1.5)
            
            MapCircle(center: center, radius: 9.144)
                .foregroundStyle(.green.opacity(0.15))
                .stroke(.green.opacity(0.8), lineWidth: 2.5)
            
            ForEach(events, id: \.id) { event in
                let distanceInMeters = Double(event.distance) * 304.8
                let geographicBearing = (userHeading + Double(event.bearing)).truncatingRemainder(dividingBy: 360.0)
                let projectedCoord = center.projected(by: distanceInMeters, bearingDegrees: geographicBearing)
                
                let profile = SoundProfile.classify(event.threatLabel)
                
                // Use the secure Set to confirm this specific dot is the leader
                let isHeadOfTrack = activeHeadIDs.contains(event.id)
                
                Annotation("", coordinate: projectedCoord) {
                    ZStack {
                        
                        // THE FIX 2: ONLY draw the Doppler velocity arrow if this is the HEAD of the track!
                        if isHeadOfTrack, let rate = event.dopplerRate, abs(rate) > 1.0 {
                            let screenRotation = event.bearing + (event.isApproaching ? 180.0 : 0.0)
                            
                            Image(systemName: "chevron.up")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(profile.color.opacity(0.8)) // Darkened slightly so it pops
                                .offset(y: -18) // Pushed outward so it clears the leading icon
                                .scaleEffect(x: 1.0, y: 1.0 + CGFloat(abs(rate) / 10.0), anchor: .bottom)
                                .rotationEffect(.degrees(screenRotation))
                        }
                        
                        // THE ICONS
                        if isHeadOfTrack && event.isEmergency {
                            // The Leader (Emergency)
                            Image(systemName: profile.icon)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(profile.color)
                                .shadow(color: profile.color, radius: 10)
                                .opacity(event.opacity)
                        } else {
                            // The Standard Traffic / Fading Tails
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
        .mapControls {
            MapCompass()
            MapUserLocationButton()
        }
        .mapControlVisibility(.hidden)
        .overlay(alignment: .bottomTrailing) {
            Button(action: {
                isTrackingUser = true
                if let loc = userLocation {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        cameraPosition = .camera(
                            MapCamera(
                                centerCoordinate: loc.coordinate,
                                distance: MapView.CAMERA_DISTANCE,
                                heading: userHeading,
                                pitch: 0
                            )
                        )
                    }
                }
            }) {
                Image(systemName: isTrackingUser ? "location.fill" : "location")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(isTrackingUser ? .blue : .gray)
                    .frame(width: 65, height: 65)
                    .background(.thickMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 40)
        }
        .onChange(of: userLocation) { _, newLocation in
            guard isTrackingUser, let loc = newLocation else { return }
            withAnimation(.default) {
                cameraPosition = .camera(
                    MapCamera(
                        centerCoordinate: loc.coordinate,
                        distance: MapView.CAMERA_DISTANCE,
                        heading: userHeading,
                        pitch: 0
                    )
                )
            }
        }
        .onChange(of: userHeading) { _, newHeading in
            guard isTrackingUser, let loc = userLocation else { return }
            withAnimation(.linear(duration: 0.2)) {
                cameraPosition = .camera(
                    MapCamera(
                        centerCoordinate: loc.coordinate,
                        distance: MapView.CAMERA_DISTANCE,
                        heading: newHeading,
                        pitch: 0
                    )
                )
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            if let userLoc = userLocation {
                let mapCenter = CLLocation(latitude: context.camera.centerCoordinate.latitude, longitude: context.camera.centerCoordinate.longitude)
                if userLoc.distance(from: mapCenter) > 50.0 {
                    isTrackingUser = false
                }
            }
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
