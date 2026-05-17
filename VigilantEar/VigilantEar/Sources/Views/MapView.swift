// MapView.swift
// VigilantEar
//
// Created by Robert Palmer (with GPU + tint fix)

import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    @Environment(AcousticCoordinator.self) private var coordinator
    @Environment(CAPAlertManager.self) private var capManager
    @EnvironmentObject var ui: UIManager
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isTrackingUser: Bool = true
    @State private var hasPerformedAutoZoom: Bool = false
    
    var events: [SoundEvent]
    var userLocation: CLLocation?
    var userHeading: Double
    
    var body: some View {
        ZStack {
            // ---------------------------------------------------------
            // 1. THE MAIN MAP LAYER
            // ---------------------------------------------------------
            Map(position: $cameraPosition, interactionModes: .all) {
                
                // 🛠 Custom Throttled User Annotation
                if let loc = userLocation {
                    Annotation(String.empty, coordinate: loc.coordinate) {
                        ZStack {
                            Image(systemName: "location.north.line.fill")
                                .font(.system(size: AppGlobals.userArrowFontSize, weight: .bold))
                                .foregroundColor(.blue.opacity(0.4))
                                .offset(y: AppGlobals.userArrowYOffset)
                                .rotationEffect(.degrees(userHeading))
                            
                            Circle()
                                .fill(Color.blue)
                                .frame(width: AppGlobals.userDotSize, height: AppGlobals.userDotSize)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 3)
                        }
                    }
                }
                
                if let route = coordinator.simulatedRoute {
                    MapPolyline(route)
                        .stroke(.red.opacity(AppGlobals.simulatedRouteOpacity), lineWidth: AppGlobals.routeLineWidth)
                }
                userLocationOverlays
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .id(userLocation?.coordinate.latitude ?? 0)          // GPU reuse optimization
            .simultaneousGesture(DragGesture().onChanged { _ in isTrackingUser = false })
            .simultaneousGesture(MagnifyGesture().onChanged { _ in isTrackingUser = false })
            .onChange(of: userLocation, initial: true) { _, newLoc in
                guard newLoc != nil else { return }
                
                if !hasPerformedAutoZoom {
                    isTrackingUser = true
                    hasPerformedAutoZoom = true
                    updateCamera(animated: true)
                } else {
                    updateCamera(animated: false)
                }
            }
            .onChange(of: userHeading) { _, _ in
                if hasPerformedAutoZoom { updateCamera(animated: false) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SnapToUser"))) { _ in
                isTrackingUser = true
                updateCamera(animated: true)
            }
            .overlay(alignment: .trailing) {
                NeuralHUD()
                    .drawingGroup(opaque: false)
                    .allowsHitTesting(false)
            }
            
            // ---------------------------------------------------------
            // 3. THE SLIDE-IN MENU DIMMER
            // ---------------------------------------------------------
            if ui.isMenuOpen {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: AppGlobals.menuSlideDuration, dampingFraction: AppGlobals.menuDamping)) {
                            ui.isMenuOpen = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            // ---------------------------------------------------------
            // 4. THE SLIDE-IN PANEL (Narrower Sidebar)
            // ---------------------------------------------------------
            GeometryReader { geometry in
                let sidebarWidth = geometry.size.width * AppGlobals.sidebarWidthMultiplier
                
                HStack(spacing: 0) {
                    Spacer()
                    
                    CustomizationsView()
                        .frame(width: sidebarWidth)
                        .background(Color(UIColor.systemGroupedBackground))
                        .ignoresSafeArea(edges: .bottom)
                        .offset(x: ui.isMenuOpen ? 0 : sidebarWidth)
                }
                .frame(width: geometry.size.width * AppGlobals.sidebarContainerMultiplier)
            }
            .zIndex(2)
        }
    }
    
    // MARK: - Computed values (cheap & always up-to-date)
    private var hasEmergencyInside500ft: Bool {
        events.contains { event in
            event.isEmergency && event.isRevealed && (event.distance * 1000.0) <= 500.0
        }
    }
    
    // MARK: - Extracted Overlays
    private var userLocationOverlays: some MapContent {
        Group {
            // --- THE SOFTENED EMERGENCY POLYGONS ---
            ForEach(capManager.nearbyAlerts) { alert in
                MapPolygon(coordinates: alert.polygon)
                    .foregroundStyle(.red.opacity(0.10))
                    .stroke(.red.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
            }
            
            if let location = userLocation {
                let center = location.coordinate
                
                // 1000ft red circle
                MapCircle(center: center, radius: AppGlobals.emergencyCircleRadiusMeters)
                    .foregroundStyle(.red.opacity(0.06))
                    .stroke(.red.opacity(0.4), lineWidth: 1)
                
                // Base 500ft yellow circle
                MapCircle(center: center, radius: AppGlobals.warningCircleRadiusMeters)
                    .foregroundStyle(.yellow.opacity(0.08))
                    .stroke(.yellow, lineWidth: 1.5)
                
                // Traveling red ring
                if hasEmergencyInside500ft {
                    Annotation(String.empty, coordinate: center) {
                        PulsingEmergencyRing()
                    }
                }
                
                // 30ft green circle
                MapCircle(center: center, radius: AppGlobals.safeCircleRadiusMeters)
                    .foregroundStyle(.green.opacity(0.15))
                    .stroke(.green.opacity(0.8), lineWidth: 2.5)
                
                // Smoothed Targets – rim-only tint for consistency with ThreatHUD
                ForEach(coordinator.mapManager.visibleTargets) { target in
                    Annotation(String.empty, coordinate: target.smoothedCoordinate) {
                        ThreatMarker(
                            currentLabel: target.currentLabel,
                            smoothedCoordinate: target.smoothedCoordinate,
                            activeEvent: target.activeEvent,
                            iconTintColor: target.iconTintColor   // used ONLY for outer rim
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Camera & Coordinate Math
    private func updateCamera(animated: Bool = false) {
        guard isTrackingUser, let loc = userLocation else { return }
        let cam = MapCamera(centerCoordinate: loc.coordinate,
                            distance: AppGlobals.defaultCameraDistance,
                            heading: userHeading)
        
        if animated {
            withAnimation(.easeInOut(duration: AppGlobals.cameraAnimationDuration)) {
                cameraPosition = .camera(cam)
            }
        } else {
            cameraPosition = .camera(cam)
        }
    }
}

// MARK: - Lightweight Pulsing Ring
struct PulsingEmergencyRing: View {
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(Color.red.opacity(0.14))
            .frame(width: AppGlobals.pulsingRingSize, height: AppGlobals.pulsingRingSize)
            .scaleEffect(isPulsing ? 1.0 : 0.1)
            .onAppear {
                withAnimation(.easeInOut(duration: AppGlobals.pulsingAnimationDuration).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - ThreatMarker Subview (UPDATED – rim-only tint)
struct ThreatMarker: View {
    let currentLabel: String
    let smoothedCoordinate: CLLocationCoordinate2D
    let activeEvent: SoundEvent?
    let iconTintColor: Color                     // ← used ONLY for the outer rim
    
    var body: some View {
        if let activeEvent = activeEvent {
            let profile = activeEvent.profile
            let mainColor = profile.color
            ZStack {
                if profile.isEmergency {
                    // Emergency icons stay bold + full fill (red/orange etc.)
                    Image(systemName: profile.icon)
                        .font(.system(size: AppGlobals.emergencyIconFontSize, weight: .bold))
                        .foregroundColor(mainColor)
                        .shadow(color: mainColor, radius: 10)
                        .overlay(
                            Circle()
                                .stroke(iconTintColor, lineWidth: AppGlobals.threatRimWidthEmergency)
                                .frame(width: 42, height: 42)
                                .opacity(AppGlobals.threatRimOpacityEmergency)
                        )
                } else {
                    // Normal icons: fill = default profile color, outer rim = vehicle-specific tint
                    Image(systemName: profile.icon)
                        .font(.system(size: AppGlobals.threatIconFontSize, weight: .semibold))
                        .foregroundColor(mainColor)          // consistent with ThreatHUD
                        .padding(AppGlobals.threatIconPadding)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(iconTintColor, lineWidth: AppGlobals.threatRimWidthNormal)
                                .frame(width: 36, height: 36)
                                .opacity(AppGlobals.threatRimOpacityNormal)
                        )
                        .shadow(radius: 3)
                }
                
                // Doppler chevron (unchanged)
                if let rate = activeEvent.dopplerRate, abs(rate) > 0.1 {
                    let pointingAngle = activeEvent.isApproaching ? (activeEvent.bearing + 180) : activeEvent.bearing
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(activeEvent.isApproaching ? .red : .green)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                        .offset(y: profile.isEmergency ? -36 : -32)
                        .rotationEffect(.degrees(pointingAngle))
                }
            }
        } else {
            EmptyView()
        }
    }
}
