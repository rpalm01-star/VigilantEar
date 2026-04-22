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
                
                // 2. Main UI Layer
                VStack {
                    // TOP BAR
                    HStack(alignment: .top) {
                        // TOP LEFT: Title & Compact Controls
                        VStack(alignment: .leading, spacing: 12) {
                            Text("VIGILANT EAR")
                                .font(.system(.headline, design: .monospaced))
                                .tracking(3)
                                .foregroundStyle(.green)
                            
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
                                        .frame(width: 20, height: 20)
                                        .padding(10)
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
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .frame(width: 20, height: 20)
                                        .padding(10)
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
                        
                        Spacer()
                    }
                    .padding(.bottom, 30)
                }
                .animation(.easeInOut, value: coordinator.activeSong)
                
                if isPortrait {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "iphone.landscape").font(.system(size: 80)).foregroundStyle(.red)
                        Text("SPATIAL ARRAY MISALIGNED").font(.title2.monospaced().bold()).foregroundStyle(.red)
                    }.zIndex(100)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                DebugHUD()
                    .padding(.bottom, 12)
                    .padding(.trailing, 12)
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

// MARK: - Debug HUD Component
struct DebugHUD: View {
    @StateObject private var monitor = SystemMonitor.shared
    @State private var isCloudLoggingEnabled: Bool = AppGlobals.logToCloud
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚙️ TELEMETRY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isCloudLoggingEnabled ? .cyan : .gray)
                .padding(.bottom, 2)
            
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
            
            HStack(spacing: 4) {
                Text("PWR:")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                
                Text("\(monitor.batteryLevel)%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(monitor.batteryLevel > 20 ? .green : .red)
                
                if monitor.isCharging {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 10))
                }
            }
        }
        .padding(10)
        .frame(width: 135, alignment: .leading)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                if isCloudLoggingEnabled {
                    Rectangle().fill(Color.blue.opacity(0.3))
                }
            }
        )
        .cornerRadius(8)
        .shadow(radius: 5)
        .onAppear {
            monitor.start()
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCloudLoggingEnabled.toggle()
                AppGlobals.logToCloud = isCloudLoggingEnabled
                
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
    }
}
