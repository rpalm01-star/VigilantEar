import SwiftUI

struct PermissionRequestView: View {
    @EnvironmentObject private var microphoneManager: MicrophoneManager
    @EnvironmentObject private var classificationService: ClassificationService
    
    var body: some View {
        VStack(spacing: 30) {
            Text("VIGILANT EAR")
                .font(.largeTitle.bold())
                .foregroundStyle(.green)
            
            Text("Microphone access required")
                .font(.title2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
            
            Button("Start Listening") {
                microphoneManager.startCapturing()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding()
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
    }
}

#Preview {
    PermissionRequestView()
        .environmentObject(MicrophoneManager(coordinator: AcousticCoordinator(), classificationService: ClassificationService()))
        .environmentObject(ClassificationService())
}
