import SwiftUI

struct ContentView: View {
    @Environment(MicrophoneManager.self) private var microphoneManager
    @Environment(AcousticCoordinator.self) private var coordinator
    
    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            
            ZStack {
                // 1. Map Stays at the Bottom
                MapView(events: coordinator.activeEvents,
                        userLocation: microphoneManager.currentLocation,
                        userHeading: microphoneManager.currentHeading)
                .ignoresSafeArea()
                
                // 2. Main UI Layer
                VStack {
                    // Top Bar
                    HStack {
                        Text("VIGILANT EAR").font(.system(.headline, design: .monospaced)).tracking(3).foregroundStyle(.green)
                        Spacer()
                        HStack(spacing: 8) {
                            Circle().fill(microphoneManager.isListening ? Color.green : Color.gray).frame(width: 8, height: 8)
                            Text(coordinator.activeEvents.last?.threatLabel.uppercased() ?? (microphoneManager.isListening ? "LISTENING..." : "OFFLINE")).font(.caption2.monospaced()).foregroundStyle(.green)
                        }
                        .padding(8).background(.ultraThinMaterial).environment(\.colorScheme, .dark).clipShape(RoundedRectangle(cornerRadius: 8))
                    }.padding()
                    
                    Spacer()
                    
                    // --- BOTTOM OVERLAY (The Fix) ---
                    ZStack(alignment: .bottom) {
                        // ThreatHUD: Forced width and height so it can't be crushed
                        HStack {
                            ThreatHUD(events: coordinator.activeEvents)
                                .frame(width: geo.size.width * 0.7, height: 100) // Fixed height & 70% width
                                .background(Color.black.opacity(0.01)) // Invisible bg to help hit testing if needed
                                .allowsHitTesting(false)
                            Spacer()
                        }
                        .padding(.leading, 20)
                        
                        // Control Column: Floating on the right
                        HStack {
                            Spacer()
                            VStack(spacing: 20) {
                                // Simulation
                                Button(action: {
                                    ThreatSimulator.runFireTruckDriveBy(location: microphoneManager.currentLocation, heading: microphoneManager.currentHeading, coordinator: coordinator)
                                }) {
                                    Image("firemanHat").resizable().scaledToFit().frame(width: 28, height: 28).padding(12).background(.ultraThinMaterial).environment(\.colorScheme, .dark).clipShape(Circle()).overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                }
                                
                                // Snap
                                Button(action: {
                                    NotificationCenter.default.post(name: NSNotification.Name("SnapToUser"), object: nil)
                                }) {
                                    Image(systemName: "location.fill").font(.system(size: 28, weight: .semibold)).foregroundColor(.blue).frame(width: 28, height: 28).padding(12).background(.ultraThinMaterial).environment(\.colorScheme, .dark).clipShape(Circle()).overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                }
                            }
                            .padding(.trailing, 20)
                        }
                    }
                    .padding(.bottom, 30) // Lifted slightly off the bottom edge
                }
                
                // 3. System Overlays (Portrait Lock / Debug)
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
            // Inside ContentView's ZStack...
            .onChange(of: isPortrait) { _, newValue in
                if newValue {
                    print("DEBUG: Orientation is Portrait. Stopping Mic.")
                    microphoneManager.stopCapturing()
                } else {
                    print("DEBUG: Orientation is Landscape. Attempting to start Mic...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        microphoneManager.startCapturing()
                    }
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                if !isPortrait {
                    print("DEBUG: Task Start - Attempting to start Mic...")
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
