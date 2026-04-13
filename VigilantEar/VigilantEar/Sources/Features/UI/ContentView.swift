import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(ClassificationService.self) private var classificationService
    @Environment(MicrophoneManager.self) private var microphoneManager
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
                    
                    // Listening indicator + current classification
                    HStack(spacing: 8) {
                        Circle()
                            .fill(microphoneManager.isListening ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        
                        Text(classificationService.currentClassification.uppercased())
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
                    runFiretruckSimulation()
                    
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
        .onAppear {
            microphoneManager.startCapturing()
        }
        .onDisappear {
            microphoneManager.stopCapturing()
        }
    }
    
    private func runFiretruckSimulation() {
        Task {
            // Generate unique ID and hidden label for stable sorting
            let truckID = UUID().uuidString.prefix(4)
            let uniqueLabel = "Siren_Approaching_\(truckID)"
            // The hidden ID is safely handled by HUD logic splitting at `_`.
            
            let targetFPS = 60.0
            //accurate real-world conversion logic preserved: 35 mph, route through center (0.0, 0.0)
            let duration: TimeInterval = 14.5
            let steps = Int(duration * targetFPS)
            let sleepTime = duration / Double(steps)
            
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let bearing = 45.0
                let signedDistance = -1.13 + (2.26 * t)
                let energy = Float(max(0.15, 1.0 - abs(signedDistance)))
                let isApproaching = signedDistance < 0
                
                let testEvent = SoundEvent(
                    timestamp: Date(),
                    threatLabel: uniqueLabel,
                    bearing: bearing,
                    distance: signedDistance,
                    energy: energy,
                    //accurate doppler rate calculation logic preserved
                    dopplerRate: isApproaching ? 15.6 : -15.6,
                    isApproaching: isApproaching
                )
                
                await MainActor.run {
                    // Filter out ONLY this specific unique ID to maintain ambient data.
                    var mixedEvents = microphoneManager.events.filter { $0.threatLabel != uniqueLabel }
                    mixedEvents.append(testEvent)
                    microphoneManager.events = mixedEvents
                }
                
                try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            }
            
            await MainActor.run {
                // When simulation ends, remove only the simulated event.
                microphoneManager.events = microphoneManager.events.filter { $0.threatLabel != uniqueLabel }
            }
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
        
        manager.isTestMode = true
        manager.toggleTestMode()   // populate test dots immediately
        
        return ContentView()
            .environment(classifier)
            .environment(manager)
        
    } catch {
        return Text("Failed to load preview: \(error.localizedDescription)")
            .foregroundStyle(.red)
    }
}
