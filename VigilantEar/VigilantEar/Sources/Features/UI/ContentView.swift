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
                    HStack {
                        Text("VIGILANT EAR")
                            .font(.system(.headline, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(.green)
                        Spacer()
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
                    
                    // THIS SPACER pushes everything below it to the bottom
                    Spacer()
                    
                    // BOTTOM OVERLAY AREA
                    HStack(alignment: .bottom) {
                        // LEFT COLUMN: Threat HUD and Shazam Text
                        VStack(alignment: .leading, spacing: 12) {
                            // 1. Threat HUD (70% of screen width)
                            ThreatHUD(events: coordinator.activeEvents)
                                .frame(width: geo.size.width * 0.7, height: 100)
                                .allowsHitTesting(false)
                            
                            // 2. Shazam Text (Now spanning the full width of the HUD)
                            if let songTitle = coordinator.activeSong,
                                coordinator.activeEvents.contains(where: { $0.threatLabel.lowercased() == "music" }) {
                                
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                    
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
                        .padding(.leading, 20)
                        
                        Spacer() // Pushes the control column to the far right
                        
                        // RIGHT COLUMN: Controls
                        VStack(spacing: 20) {
                            // Simulation Button
                            Button(action: {
                                ThreatSimulator.runFireTruckDriveBy(location: microphoneManager.currentLocation, heading: microphoneManager.currentHeading, coordinator: coordinator)
                            }) {
                                Image("firemanHat").resizable().scaledToFit().frame(width: 28, height: 28).padding(12).background(.ultraThinMaterial).environment(\.colorScheme, .dark).clipShape(Circle()).overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                            
                            // Snap to User Button
                            Button(action: {
                                NotificationCenter.default.post(name: NSNotification.Name("SnapToUser"), object: nil)
                            }) {
                                Image(systemName: "location.fill").font(.system(size: 28, weight: .semibold)).foregroundColor(.blue).frame(width: 28, height: 28).padding(12).background(.ultraThinMaterial).environment(\.colorScheme, .dark).clipShape(Circle()).overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            }
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.bottom, 30) // Final lift off the bottom edge
                }
                .animation(.easeInOut, value: coordinator.activeSong)
                
                // 3. Orientation Lock Overlay
                if isPortrait {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "iphone.landscape").font(.system(size: 80)).foregroundStyle(.red)
                        Text("SPATIAL ARRAY MISALIGNED").font(.title2.monospaced().bold()).foregroundStyle(.red)
                    }.zIndex(100)
                }
            }
            .overlay(alignment: .topLeading) {
                DebugHUD().padding(.top, 60).padding(.leading, 16)
            }
            // ... (Rest of your onChange and task logic exactly as before)
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

// MARK: - Debug HUD Component
struct DebugHUD: View {
    @StateObject private var monitor = SystemMonitor.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚙️ SYSTEM TELEMETRY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            
            HStack {
                Text("CPU:")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Text("\(String(format: "%.1f", monitor.cpuUsage))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(monitor.cpuUsage > 80.0 ? .red : .green)
            }
            
            HStack {
                Text("RAM:")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Text("\(String(format: "%.1f", monitor.memoryUsageMB)) MB")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(radius: 5)
        .onAppear {
            monitor.start()
        }
    }
}
