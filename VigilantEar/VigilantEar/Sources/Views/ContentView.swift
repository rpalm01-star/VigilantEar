import SwiftUI

struct ContentView: View {
    @Environment(MicrophoneManager.self) private var microphoneManager
    @Environment(AcousticCoordinator.self) private var coordinator
    @Environment(CAPAlertManager.self) private var capManager
    
    @State private var showLegalSheet = false // --- ADDED LEGAL STATE ---
    
    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            
            ZStack {
                // 1. Map Layer
                MapView(events: coordinator.activeEvents,
                        userLocation: microphoneManager.currentLocation,
                        userHeading: microphoneManager.currentHeading)
                .ignoresSafeArea()
                
                // 2. Main UI Layer
                VStack {
                    // TOP BAR
                    HStack(alignment: .top) {
                        // TOP LEFT: Title & Compact Controls
                        VStack(alignment: .leading, spacing: 12) {
                            
                            Text(AppGlobals.appTitle)
                                .font(.system(.headline, design: .monospaced))
                                .tracking(3)
                                .foregroundStyle(.black)
                                .background {
                                    Text(AppGlobals.appTitle)
                                        .font(.system(.headline, design: .monospaced))
                                        .tracking(3)
                                        .foregroundStyle(AppGlobals.darkGray.opacity(0.9))
                                        .blur(radius: 10)
                                }
                                .overlay {
                                    Text(AppGlobals.appTitle)
                                        .font(.system(.headline, design: .monospaced))
                                        .tracking(3)
                                        .foregroundStyle(.green)
                                        .blur(radius: 0.9)
                                }
                            
                            // THE COMPACT CONTROLS
                            HStack(spacing: 12) {
                                Button(action: {
                                    ThreatSimulator.runFireTruckDriveBy(location: microphoneManager.currentLocation,
                                                                        heading: microphoneManager.currentHeading,
                                                                        coordinator: coordinator)
                                }) {
                                    Image("firemanHat")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 45, height: 45)
                                        .padding(2)
                                        .background(.ultraThinMaterial)
                                        .environment(\.colorScheme, .dark)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                }
                                
                                Button(action: {
                                    NotificationCenter.default.post(name: NSNotification.Name("SnapToUser"), object: nil)
                                }) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .frame(width: 45, height: 45)
                                        .padding(2)
                                        .background(.ultraThinMaterial)
                                        .environment(\.colorScheme, .dark)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // TOP RIGHT: Status Pill
                        HStack(spacing: 8) {
                            Circle()
                                .fill(microphoneManager.isListening ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(coordinator.activeEvents.last?.threatLabel.uppercased() ?? (microphoneManager.isListening ? "LISTENING..." : "OFFLINE"))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.green)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                    
                    Spacer()
                    
                    // BOTTOM OVERLAY AREA (Threats, Shazam, Legal, & CAP Banner)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 12) {
                            ThreatHUD(events: coordinator.activeEvents)
                                .frame(width: geo.size.width * 0.7, height: 100)
                                .allowsHitTesting(false)
                            
                            if let songTitle = coordinator.activeSong,
                               coordinator.activeEvents.contains(where: { $0.threatLabel.lowercased() == "music" }) {
                                
                                HStack(alignment: .center, spacing: 8) {
                                    Text(songTitle)
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .id(songTitle)
                                .frame(width: geo.size.width * 0.7, alignment: .leading)
                                .transition(unsafe .asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                            
                            // --- LEGAL BUTTON & CAP BANNER GROUP ---
                            HStack(spacing: 12) {
                                // 1. Legal Button (Always visible)
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
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .fill(Color.black.opacity(0.10))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 5)
                                                                .stroke(Color.cyan.opacity(0.25), lineWidth: 0.8)
                                                        )
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .fill(Color.cyan.opacity(0.0))
                                                        .frame(width: geo.size.width * 0.0)
                                                }
                                            }
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                
                                // 2. CAP Emergency Banner
                                if let activeAlert = capManager.nearbyAlerts.first {
                                    // NO MORE STRING HACKING HERE
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 14, weight: .bold))
                                        
                                        // JUST USE THE DIRECT EVENT TAG
                                        Text(activeAlert.event.uppercased())
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.red.opacity(0.6))
                                    .foregroundStyle(.white.opacity(0.95))
                                    .clipShape(Capsule())
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                }
                            }
                        }
                        .padding(.leading, 10)
                        
                        Spacer()
                    }
                    .padding(.bottom, 15)
                }
                .animation(.easeInOut, value: coordinator.activeSong)
                .animation(.easeInOut, value: capManager.nearbyAlerts.count)
                
                if isPortrait {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text(AppGlobals.appTitle)
                            .font(.system(.headline, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(.black)
                            .background {
                                Text(AppGlobals.appTitle)
                                    .font(.system(.headline, design: .monospaced))
                                    .tracking(3)
                                    .foregroundStyle(.mint.opacity(0.9))
                                    .blur(radius: 10)
                            }
                            .overlay {
                                Text(AppGlobals.appTitle)
                                    .font(.system(.headline, design: .monospaced))
                                    .tracking(3)
                                    .foregroundStyle(.green)
                                    .blur(radius: 0.9)
                            }
                        Image(systemName: "iphone.landscape").font(.system(size: 80)).foregroundStyle(.red)
                        Text("SPATIAL ARRAY MISALIGNED").font(.title2.monospaced().bold()).foregroundStyle(.red)
                        Text("(Turn to landscape mode)").font(.title2.monospaced().bold()).foregroundStyle(.white)
                    }.zIndex(100)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                DebugHUD(manager: microphoneManager, roadManager: microphoneManager.roadManager)
                    .padding(.bottom, 12)
                    .padding(.trailing, 12)
            }
            .sheet(isPresented: $showLegalSheet) {
                LegalView()
            }
            .onChange(of: microphoneManager.currentLocation) { _, newLocation in
                if let location = newLocation {
                    microphoneManager.roadManager.processLocationUpdate(location)
                }
            }
            .onChange(of: isPortrait) { _, newValue in
                if newValue {
                    microphoneManager.stopCapturing()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        microphoneManager.startCapturing()
                    }
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                if !isPortrait {
                    microphoneManager.startCapturing()
                }
            }
            .onDisappear {
                microphoneManager.stopCapturing()
            }
        }
    }
}
