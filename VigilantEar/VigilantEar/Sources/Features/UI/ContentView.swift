import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(MicrophoneManager.self) private var microphoneManager
    @Environment(AcousticCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 6) {
                // Title + Live HUD
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
                        
                        // ✅ FIX: Read the live data! If there are active dots, show the newest one. Otherwise, show Listening.
                        let statusText = coordinator.activeEvents.last?.threatLabel.uppercased() ?? (microphoneManager.isListening ? "LISTENING..." : "OFFLINE")
                        
                        Text(statusText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 0)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .lineLimit(1)
                .padding(.horizontal, 0)
                .frame(maxWidth: .infinity)
                
                RadarView()
                    .frame(maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 0)
                    .padding(.vertical, 0)
                    .padding(.bottom, 0)
                    .padding(.top, 0)
                
                Spacer()
                
                Button(action: {
                    // Run the visual UI simulation
                    simulateFireTruck()
                    
                    // DROP A REAL EVENT INTO THE DATABASE QUEUE
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
                    Image("firemanHat") // External fireman hat asset from project assets
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 32)
                }
            }
            .padding(.top, 0)
            .padding(.bottom, 0)
        }
        .task {
            // Wait 300ms to guarantee VigilantEarApp has wired the pipeline to the mic
            try? await Task.sleep(for: .milliseconds(300))
            microphoneManager.startCapturing()
        }
        .onDisappear {
            microphoneManager.stopCapturing()
        }
    }
    
    func simulateFireTruck() {
        var step: Double = 0
        let totalSteps: Double = 30
        
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            step += 1
            
            // 1. VIRTUAL PATH: Straight line from Bottom-Left to Top-Right
            // Using a 40-unit grid to ensure it starts/ends outside the 30ft rings
            let x = -20.0 + (step * 1.33)
            let y = -20.0 + (step * 1.33)
            
            // 2. CONVERT TO RADAR DATA
            let distanceInFeet = sqrt(x*x + y*y)
            let bearing = atan2(x, y) * 180 / .pi
            
            // 3. NORMALIZE FOR RADAR (30ft scale)
            let normalizedDistance = min(1.0, distanceInFeet / 30.0)
            
            let event = SoundEvent(
                threatLabel: "Fire_Truck", // SoundEvent init handles "Fire" -> Red
                bearing: bearing,
                distance: normalizedDistance,
                energy: 0.9
            )
            
            DispatchQueue.main.async {
                // FIX: Ensure this points to your coordinator instance
                self.coordinator.addEvent(event)
            }
            
            if step >= totalSteps { timer.invalidate() }
        }
    }
}

// MARK: - Preview
#Preview {
    do {
        // Create the in-memory database for the preview canvas
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SoundEvent.self, configurations: config)
        
        let coordinator = AcousticCoordinator()
        let classifier = ClassificationService()
        
        let manager = MicrophoneManager(
            coordinator: coordinator,
            classificationService: classifier,
            container: container // Inject the temporary container
        )
        
        // FIX: Removed the old toggleTestMode calls that no longer exist
        
        return ContentView()
            .environment(classifier)
            .environment(manager)
        // FIX: Inject the coordinator into the preview environment
            .environment(coordinator)
        
    } catch {
        return Text("Failed to load preview: \(error.localizedDescription)")
            .foregroundStyle(.red)
    }
}
