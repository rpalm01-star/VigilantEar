import SwiftUI

struct ContentView: View {
    @Environment(MicrophoneManager.self) private var microphoneManager
    @Environment(AcousticCoordinator.self) private var coordinator
    @Environment(CAPAlertManager.self) private var capManager
    @EnvironmentObject var ui: UIManager
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            
            ZStack {
                // 1. Map Layer (🚨 DELETE BottomActionBar FROM THE MAPVIEW FILE!)
                MapView(events: coordinator.activeEvents,
                        userLocation: microphoneManager.currentLocation,
                        userHeading: microphoneManager.currentHeading)
                .ignoresSafeArea()
                
                // 2. Main UI Layer
                VStack(alignment: .leading, spacing: 0) {
                    
                    // --- TOP DASHBOARD BAR ---
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            // Clear the Notch for the "V"
                            AppTitleView()
                                .padding(.leading, 14)
                            StatusPillView()
                                .padding(.leading, 14)
                        }
                        Spacer()
                        AlertPillView()
                            .padding(.top, 14)
                            .padding(.trailing, 50)
                            .frame(maxWidth: geo.size.width * 0.67, alignment: .trailing)
                            .drawingGroup(opaque: true)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                    
                    Spacer()
                    
                    // --- BOTTOM OVERLAY AREA ---
                    ZStack(alignment: .bottom) {
                        
                        // LAYER 1: DATA (Threats & Song Title)
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                
                                ThreatHUD(events: coordinator.activeEvents)
                                    .frame(width: geo.size.width * 0.75, height: 84, alignment: .leading)
                                    .allowsHitTesting(false)
                                
                                if let songTitle = coordinator.activeSong,
                                   coordinator.activeEvents.contains(where: { $0.threatLabel.lowercased() == "music" }) {
                                    
                                    // Stripping the music note character (if present)
                                    let cleanTitle = songTitle
                                        .replacingOccurrences(of: "♫", with: "")
                                        .replacingOccurrences(of: "🎵", with: "")
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    Text(cleanTitle)
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .lineLimit(2) // 🚨 Your updated line limit
                                        .multilineTextAlignment(.leading)
                                        .padding(.leading, 4)
                                    // Keep it from pushing into the Action Bar's space
                                        .frame(maxWidth: geo.size.width * 0.4, alignment: .leading)
                                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                                }
                            }
                            .padding(.leading, 8)
                            .padding(.bottom, 32)
                            
                            Spacer() // Ensures the HStack fills the width
                        }
                        
                        // LAYER 2: THE ACTION BAR
                        BottomActionBar()
                            .padding(.bottom, 12)
                            .opacity(0.65)
                            .drawingGroup(opaque: false)
                            .zIndex(10)
                    }
                    // 🚨 THE CENTERING FIX: Forces the ZStack to span the full screen width
                    .frame(maxWidth: .infinity)
                }
                .ignoresSafeArea()
                
                // 3. LANDSCAPE LOCK
                if isPortrait {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 20) {
                        AppTitleView()
                        Image(systemName: "iphone.landscape").font(.system(size: 80)).foregroundStyle(.red)
                        Text(AppGlobals.spatialArrayMisaligned).font(.title2.monospaced().bold()).foregroundStyle(.red)
                        Text(AppGlobals.turnToLandscape).font(.title2.monospaced().bold()).foregroundStyle(.white)
                    }
                    .zIndex(100)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack() {
                    DebugHUD()
                }
                .padding(.bottom, -12)
                .padding(.trailing, -50)
                .opacity(isPortrait ? 0.0 : 1.0)
            }
            .onChange(of: microphoneManager.currentLocation) { _, newLocation in
                if let location = newLocation {
                    DependencyContainer.shared.roadManager.processLocationUpdate(location)
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
            .environment(\.locale, Locale(identifier: preferredLanguage))
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                if !isPortrait { microphoneManager.startCapturing() }
            }
            .onDisappear {
                AppGlobals.doLog(message: "🛑 View disappeared. Stopping microphone capture.", step: "ContentView: .onDisappear")
                microphoneManager.stopCapturing()
            }
            .tint(.green.opacity(0.75))
        }
    }
}
