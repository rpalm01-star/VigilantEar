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
                
                // Radar dominates the screen
                RadarView()
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 8)
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
