import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(MicrophoneManager.self) private var microphoneManager
    @Environment(AcousticCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        // GEOMETRY READER: Flawlessly detects the drawn frame instead of the gyroscope
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
                    
                    // Bottom Section: Floating Button & Threat Scroller
                    HStack(alignment: .bottom) {
                        
                        // Floating Simulation Button
                        Button(action: {
                            ThreatSimulator.runFireTruckDriveBy(
                                location: microphoneManager.currentLocation,
                                heading: microphoneManager.currentHeading,
                                coordinator: coordinator
                            )
                            
                            let testDbEvent = SoundEvent(
                                timestamp: Date(),
                                threatLabel: "Simulated_Firetruck_Database_Test",
                                bearing: 45.0,
                                distance: 0.5,
                                energy: 0.8,
                                dopplerRate: 15.6,
                                isApproaching: true
                            )
                            modelContext.insert(testDbEvent)
                            try? modelContext.save()
                            
                        }) {
                            Image("firemanHat")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                .shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 5)
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, 40)
                        
                        Spacer()

                        ThreatHUD(events: coordinator.activeEvents)
                            .frame(height: 80) // Bumped height slightly to fit the new text labels
                            .padding(.bottom, 20)
                    }
                }
                
                // --- 3. TACTICAL WARNING OVERLAY ---
                // Because the app rotates freely, this VStack naturally aligns perfectly upright!
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
                            
                            Text("VigilantEar requires Landscape orientation to track acoustic phase delays. Please rotate your device.")
                                .font(.callout.monospaced())
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                    .zIndex(100)
                }
            }
            // --- 4. HARDWARE LISTENERS ---
            // Reacts instantly to the layout engine changing shapes
            .onChange(of: isPortrait) { oldValue, newValue in
                if newValue {
                    // Switched to Portrait: Kill the mic so we don't log bad math
                    microphoneManager.stopCapturing()
                } else {
                    // Switched to Landscape: Give the UI 500ms to settle, then fire up the array
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
