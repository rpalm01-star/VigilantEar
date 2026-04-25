import SwiftUI

struct ContentView: View {
    @Environment(MicrophoneManager.self) private var microphoneManager
    @Environment(AcousticCoordinator.self) private var coordinator
    
    let title = "VIGILANT EAR"
    
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
                            
                            Text(title)
                                .font(.system(.headline, design: .monospaced))
                                .tracking(3)
                                .foregroundStyle(.black)
                                .background {
                                    // Soft mint background glow (behind everything)
                                    Text(title)
                                        .font(.system(.headline, design: .monospaced))
                                        .tracking(3)
                                        .foregroundStyle(AppGlobals.darkGray.opacity(0.9))
                                        .blur(radius: 10)
                                }
                                .overlay {
                                    Text(title)
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
                        Text(title)
                            .font(.system(.headline, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(.black)
                            .background {
                                // Soft mint background glow (behind everything)
                                Text(title)
                                    .font(.system(.headline, design: .monospaced))
                                    .tracking(3)
                                    .foregroundStyle(.mint.opacity(0.9))
                                    .blur(radius: 10)
                            }
                            .overlay {
                                Text(title)
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
                DebugHUD(manager: microphoneManager)
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

struct DebugHUD: View {
    
    @Bindable var manager: MicrophoneManager
    @StateObject private var monitor = SystemMonitor.shared
    @State private var isCloudLoggingEnabled: Bool = AppGlobals.logToCloud
    
    let telemetryTitle = "⚙️ Telemetry" + AppGlobals.appVersion
    
    // Computed thermal state
    private var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }
    
    // Smart CPU color thresholds
    private var cpuColor: Color {
        let usage = monitor.cpuUsage
        if usage > 300 {
            return .red
        } else if usage > 150 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var thermalIcon: String {
        switch thermalState {
        case .nominal:   return "thermometer.low"
        case .fair:      return "thermometer.medium"
        case .serious:   return "thermometer.high"
        case .critical:  return "flame.fill"
        @unknown default: return "thermometer"
        }
    }
    
    private var thermalColor: Color {
        switch thermalState {
        case .nominal:   return .green
        case .fair:      return .yellow
        case .serious:   return .orange
        case .critical:  return .red
        @unknown default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(telemetryTitle)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isCloudLoggingEnabled ? .cyan : .gray)
                .padding(.bottom, 2)
            
            // === CPU with Thermal Indicator ===
            // === CPU with Smart Thresholds ===
            HStack() {
                Text("CPU:")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                
                Text("\(String(format: "%.1f", monitor.cpuUsage))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(cpuColor)
                
                Image(systemName: thermalIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(thermalColor)
            }
            
            HStack {
                Text("RAM:")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Text("\(String(format: "%.1f", monitor.memoryUsageMB)) MB")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }
            
            HStack {
                Text("BAT:")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                
                Text("\(monitor.batteryLevel)%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(monitor.batteryLevel > 20 ? .green : .red)
                Image(systemName: thermalIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(thermalColor)
                if monitor.isCharging {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 11))
                }
            }
            
            HStack {
                Text("MIC:")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                
                Text("\(manager.activeMicCount)" + (manager.activeMicCount >= 2 ? " stereo" : " mono"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(manager.activeMicCount > 0 ? .green : .red)
                    .contentTransition(.numericText())
            }
        }
        .padding(4)
        .frame(width: 112, alignment: .leading)
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
