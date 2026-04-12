import SwiftUI

struct ContentView: View {
    @Environment(ClassificationService.self) private var classificationService
    @Environment(MicrophoneManager.self) private var microphoneManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 12) {
                // Title + Live HUD
                HStack {
                    Text("VIGILANT EAR")
                        .font(.system(.headline, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.green)
                    
                    Spacer()
                    
                    // Listening indicator + current classification
                    HStack(spacing: 6) {
                        Circle()
                            .fill(microphoneManager.isListening ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        
                        
                        Text(classificationService.currentClassification.uppercased())
                            .font(.caption2.monospaced())
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal)
                
                RadarView()
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 8)
                
                // --- NEW SMALL THEMATIC BUTTON ---
                HStack {
                    Button(action: {
                        runFiretruckSimulation()
                    }) {
                        Image("firemanHat") // External fireman hat asset from project assets
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                            .padding()
                            .background(Color.red.opacity(0.15))
                            .clipShape(Rectangle())
                            .overlay(Rectangle().stroke(Color.red.opacity(0.5), lineWidth: 1.5))
                        //Styled to highlight on a touch
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.top, 20)
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
    let coordinator = AcousticCoordinator()
    let classifier = ClassificationService()
    let manager = MicrophoneManager(
        coordinator: coordinator,
        classificationService: classifier
    )
    manager.isTestMode = true
    manager.toggleTestMode()   // populate test dots immediately
    
    return ContentView()
        .environment(classifier)
        .environment(manager)
}
