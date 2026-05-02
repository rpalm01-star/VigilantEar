import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @Environment(AcousticCoordinator.self) private var coordinator
    @State private var showLegalSheet = false
    
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
            userLocationOverlays
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
        .overlay(alignment: .trailing) {
            NeuralTickerHUD()
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showLegalSheet = true
            } label: {
                Text("Legal")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .underline()
                    .background(
                        GeometryReader { geo in
                            ZStack(alignment: .trailing) {
                                // Base background (same as ticker)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.black.opacity(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Color.cyan.opacity(0.25), lineWidth: 0.8)
                                    )
                                
                                // 0% confidence fill (almost invisible)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.cyan.opacity(0.0))   // 0% fill
                                    .frame(width: geo.size.width * 0.0)
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.trailing, 30)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showLegalSheet) {
            LegalView()
        }
    }
    
    // MARK: - Extracted Overlays (Fixed opaque return type)
    private var userLocationOverlays: some MapContent {
        Group {
            if let location = userLocation {
                let center = location.coordinate
                let hasEmergencyInside500ft = events.contains { event in
                    event.isEmergency && event.isRevealed && (event.distance * 1000.0) <= 500.0
                }
                
                // 1000ft red circle
                MapCircle(center: center, radius: 304.8)
                    .foregroundStyle(.red.opacity(0.06))
                    .stroke(.red.opacity(0.4), lineWidth: 1)
                
                // Base 500ft yellow circle
                MapCircle(center: center, radius: 152.4)
                    .foregroundStyle(.yellow.opacity(0.08))
                    .stroke(.yellow, lineWidth: 1.5)
                
                // Traveling red ring
                if hasEmergencyInside500ft {
                    let t = Date().timeIntervalSince1970 * 1.4
                    let progress = (sin(t) + 1) / 2
                    let ringRadius = 15 + (progress * 137)
                    let ringOpacity = 0.02 + (progress * 0.12)
                    
                    MapCircle(center: center, radius: ringRadius)
                        .foregroundStyle(.red.opacity(ringOpacity))
                }
                
                // 30ft green circle
                MapCircle(center: center, radius: 9.144)
                    .foregroundStyle(.green.opacity(0.15))
                    .stroke(.green.opacity(0.8), lineWidth: 2.5)
                
                // Comet Tails
                ForEach(getCrispTail(from: events, center: center)) { event in
                    if event.isRevealed {
                        let coord = getProjectedCoordinate(for: event, center: center)
                        Annotation("", coordinate: coord) {
                            Circle()
                                .fill(event.dotColor)
                                .frame(width: 14 * event.visualScale, height: 14 * event.visualScale)
                                .opacity(event.opacity * 0.4)
                                .blendMode(.screen)
                        }
                    }
                }
                
                // Smoothed Targets
                ForEach(coordinator.mapManager.visibleTargets) { target in
                    let sessionID = target.id
                    let activeEvent = events.last(where: { $0.sessionID == sessionID })
                    
                    Annotation("", coordinate: target.smoothedCoordinate) {
                        ThreatMarker(
                            currentLabel: target.currentLabel,
                            smoothedCoordinate: target.smoothedCoordinate,
                            activeEvent: activeEvent
                        )
                    }
                }
            }
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
    
    private func getCrispTail(from rawEvents: [SoundEvent], center: CLLocationCoordinate2D) -> [SoundEvent] {
        var crispTail: [SoundEvent] = []
        let grouped = Dictionary(grouping: rawEvents, by: { $0.sessionID })
        
        for (_, sessionEvents) in grouped {
            var lastAddedCoord: CLLocationCoordinate2D? = nil
            let sortedEvents = sessionEvents.sorted(by: { $0.timestamp < $1.timestamp })
            
            for event in sortedEvents {
                let currentCoord = getProjectedCoordinate(for: event, center: center)
                
                if let lastCoord = lastAddedCoord {
                    let loc1 = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                    let loc2 = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
                    
                    if loc1.distance(from: loc2) >= 0.5 {
                        crispTail.append(event)
                        lastAddedCoord = currentCoord
                    }
                } else {
                    crispTail.append(event)
                    lastAddedCoord = currentCoord
                }
            }
        }
        
        return crispTail
    }
}

// MARK: - Extracted Threat Marker
private struct ThreatMarker: View {
    let currentLabel: String
    let smoothedCoordinate: CLLocationCoordinate2D
    let activeEvent: SoundEvent?
    
    var body: some View {
        let profile = SoundProfile.classify(currentLabel)
        
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
            
            if let event = activeEvent, let rate = event.dopplerRate, abs(rate) > 0.1 {
                let pointingAngle = event.isApproaching ? (event.bearing + 180) : event.bearing
                
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(event.isApproaching ? .red : .green)
                    .shadow(color: .black.opacity(0.8), radius: 2)
                    .offset(y: profile.isEmergency ? -36 : -32)
                    .rotationEffect(.degrees(pointingAngle))
            }
        }
    }
}
