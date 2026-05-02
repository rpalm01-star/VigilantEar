import SwiftUI

struct ContentView: View {
    @Environment(MicrophoneManager.self) private var microphoneManager
    @Environment(AcousticCoordinator.self) private var coordinator
    
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
                            
                            Text(AppGlobals.applicationTitle)
                                .font(.system(.headline, design: .monospaced))
                                .tracking(3)
                                .foregroundStyle(.black)
                                .background {
                                    // Soft mint background glow (behind everything)
                                    Text(AppGlobals.applicationTitle)
                                        .font(.system(.headline, design: .monospaced))
                                        .tracking(3)
                                        .foregroundStyle(AppGlobals.darkGray.opacity(0.9))
                                        .blur(radius: 10)
                                }
                                .overlay {
                                    Text(AppGlobals.applicationTitle)
                                        .font(.system(.headline, design: .monospaced))
                                        .tracking(3)
                                        .foregroundStyle(.green)
                                        .blur(radius: 0.9)                   // ← tweak this for outline thickness
                                }
                            
                            // THE COMPACT CONTROLS (Size locked to 40x40)
                            HStack(spacing: 12) {
                                // Simulation Button (Fire First)
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
                                
                                // Snap to User Button (Nav Second)
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
                    
                    // BOTTOM OVERLAY AREA (Threats & Shazam)
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
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }
                        .padding(.leading, 10)
                        
                        Spacer()
                    }
                    .padding(.bottom, 15)
                }
                .animation(.easeInOut, value: coordinator.activeSong)
                
                if isPortrait {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text(AppGlobals.applicationTitle)
                            .font(.system(.headline, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(.black)
                            .background {
                                // Soft mint background glow (behind everything)
                                Text(AppGlobals.applicationTitle)
                                    .font(.system(.headline, design: .monospaced))
                                    .tracking(3)
                                    .foregroundStyle(.mint.opacity(0.9))
                                    .blur(radius: 10)
                            }
                            .overlay {
                                Text(AppGlobals.applicationTitle)
                                    .font(.system(.headline, design: .monospaced))
                                    .tracking(3)
                                    .foregroundStyle(.green)
                                    .blur(radius: 0.9)                   // ← tweak this for outline thickness
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
            // Bridge the GPS from the Mic Manager to the Road Manager
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
        }
    }
}
