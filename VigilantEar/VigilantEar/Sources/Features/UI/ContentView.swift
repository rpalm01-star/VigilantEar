import SwiftUI

struct ContentView: View {
    @Environment(ClassificationService.self) private var classificationService
    @Environment(MicrophoneManager.self) private var microphoneManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 4) {
                Text("Vigilant Ear")
                    .font(.system(.headline, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.green)

                // The HUD Readout
                ZStack {
                    if let detection = microphoneManager.latestDetection {
                        Text(detection)
                            .font(.caption2)
                            .monospaced()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    } else {
                        Text("STANDBY")
                            .font(.caption2)
                            .monospaced()
                            .opacity(0.2)
                    }
                }
                .frame(height: 20) // Keeps the RadarView from jumping
                
                RadarView()
            }
        }
        .onAppear {
            microphoneManager.startCapturing()
        }
    }
}

#Preview {
    ContentView()
        .environment(ClassificationService())
        .environment(MicrophoneManager(coordinator: AcousticCoordinator(), classificationService: ClassificationService()))
}
