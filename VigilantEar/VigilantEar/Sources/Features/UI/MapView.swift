import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    
    static let CAMERA_DISTANCE: Double = Double(400)
    
    var events: [SoundEvent]
    var userLocation: CLLocation?
    var userHeading: Double
    
    // THE FIX: Start with a fully automatic position
    @State private var cameraPosition: MapCameraPosition = .automatic
        
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
        let freshHeads = heads.values.filter { $0.age < 4.0 }
        return Set(freshHeads.map { $0.id })
    }
    
    var body: some View {
        Map(
            position: $cameraPosition,
            bounds: MapCameraBounds(
                minimumDistance: 100,
                maximumDistance: 800
            ),
            interactionModes: .all
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
                let isHeadOfTrack = activeHeadIDs.contains(event.id)
                
                Annotation("", coordinate: projectedCoord) {
                    ZStack {
                        if isHeadOfTrack, let rate = event.dopplerRate, abs(Double(rate)) > 1.0 {
                            let chevronFont = Font.system(size: 14, weight: .black)
                            let chevronColor = profile.color.opacity(0.8)
                            let scaleY = 1.0 + CGFloat(abs(Double(rate)) / 10.0)
                            let screenRotation = event.bearing + (event.isApproaching ? 180.0 : 0.0)
                            Image(systemName: "chevron.up")
                                .font(chevronFont)
                                .foregroundColor(chevronColor)
                                .offset(y: -18)
                                .scaleEffect(x: 1.0, y: scaleY, anchor: .bottom)
                                .rotationEffect(.degrees(screenRotation))
                        }
                        
                        if isHeadOfTrack && profile.isEmergency {
                            let emergencyFont = Font.system(size: 24, weight: .bold)
                            let primaryColor = profile.color
                            Image(systemName: profile.icon)
                                .font(emergencyFont)
                                .foregroundColor(primaryColor)
                                .shadow(color: primaryColor, radius: 10)
                                .opacity(event.opacity)
                        } else {
                            let primaryColor = profile.color
                            let circleFont = Font.system(size: 16)
                            let opacityValue = event.opacity
                            let visualScale = CGFloat(max(0.6, event.visualScale))
                            let opacityScale = CGFloat(max(0.3, opacityValue))
                            let combinedScale = visualScale * opacityScale
                            let shadowRadius = CGFloat(event.energy) * 15
                            Image(systemName: "circle.fill")
                                .font(circleFont)
                                .foregroundColor(primaryColor)
                                .opacity(opacityValue)
                                .scaleEffect(combinedScale)
                                .shadow(color: primaryColor, radius: shadowRadius)
                        }
                    }
                }
            }
        }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .overlay(alignment: .bottomTrailing) {
            Button(action: {
                if let loc = userLocation {
                    // Force a hard snap back to the current location with a crisp animation
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
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
                Image(systemName: "location.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 65, height: 65)
                    .background(.thickMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 40)
        }
        .onChange(of: userLocation) { _, newLocation in
            if let loc = userLocation {
                cameraPosition = .camera(
                    MapCamera(
                        centerCoordinate: loc.coordinate,
                        distance: MapView.CAMERA_DISTANCE,
                        heading: userHeading
                    )
                )
            }
        }
        .onChange(of: userHeading) { _, newHeading in
            if let loc = userLocation {
                cameraPosition = .camera(
                    MapCamera(
                        centerCoordinate: loc.coordinate,
                        distance: MapView.CAMERA_DISTANCE,
                        heading: newHeading
                    )
                )
            }
        }
        .onAppear {
            // Initial snap-to-user if GPS is already ready
            if let loc = userLocation {
                cameraPosition = .camera(
                    MapCamera(
                        centerCoordinate: loc.coordinate,
                        distance: MapView.CAMERA_DISTANCE,
                        heading: userHeading
                    )
                )
            }
        }
    }
}

// MARK: - Local Extension
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
