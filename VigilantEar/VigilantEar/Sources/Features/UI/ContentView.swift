import SwiftUI

struct ContentView: View {
    @Environment(MicrophoneManager.self) private var microphoneManager
    @Environment(AcousticCoordinator.self) private var coordinator
    
    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            
            ZStack {
                // --- 1. THE MAP BACKGROUND ---
                MapView(
                    events: coordinator.activeEvents,
                    userLocation: microphoneManager.currentLocation,
                    userHeading: microphoneManager.currentHeading
                )
                .ignoresSafeArea()
                
                // --- 2. HUD OVERLAYS ---
                VStack {
                    // Top Status Bar Overlay
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
                            
                            let statusText = coordinator.activeEvents.last?.threatLabel.uppercased() ?? (microphoneManager.isListening ? "LISTENING..." : "OFFLINE")
                            
                            Text(statusText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.green)
                                .lineLimit(1)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                    
                    Spacer()
                    
                    // --- THE FIX: LEFT-JUSTIFIED & CENTER-ALIGNED BOTTOM BAR ---
                    HStack(alignment: .top, spacing: 6) {
                        
                        // 1. Simulation Button
                        Button(action: {
                            ThreatSimulator.runFireTruckDriveBy(
                                location: microphoneManager.currentLocation,
                                heading: microphoneManager.currentHeading,
                                coordinator: coordinator
                            )
                        }) {
                            Image("firemanHat")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                .shadow(color: .black.opacity(0.3), radius: 4)
                        }

                        // Push everything to the left
                        Spacer()

                        // 3. The Threat Scroller
                        ThreatHUD(events: coordinator.activeEvents)
                            .frame(height: 80)
                            .allowsHitTesting(false)
                        
                        // Push everything to the left
                        Spacer()
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 10)
                }
                
                // --- 3. TACTICAL WARNING OVERLAY ---
                if isPortrait {
                    ZStack {
                        Color.black.opacity(0.85)
                            .ignoresSafeArea()
                            .background(.ultraThinMaterial)
                        
                        VStack(spacing: 20) {
                            Image(systemName: "iphone.landscape")
                                .font(.system(size: 80))
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse, isActive: true)
                            
                            Text("SPATIAL ARRAY MISALIGNED")
                                .font(.title2.monospaced().bold())
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                            
                            Text("VigilantEar requires Landscape orientation to track acoustic phase delays.")
                                .font(.callout.monospaced())
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                    .zIndex(100)
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
            // --- 4. SYSTEM TELEMETRY OVERLAY ---
            .overlay(alignment: .topLeading) {
                DebugHUD()
                    .padding(.top, 50)
                    .padding(.leading, 16)
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
