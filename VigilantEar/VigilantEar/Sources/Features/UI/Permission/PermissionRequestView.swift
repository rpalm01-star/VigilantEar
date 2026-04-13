import SwiftUI
import SwiftData

struct PermissionRequestView: View {
    @Environment(ClassificationService.self) private var classificationService
    @Environment(MicrophoneManager.self) private var microphoneManager
    
    var body: some View {
        VStack(spacing: 40) {
            
            // Added an icon to match the technical aesthetic
            Image(systemName: "waveform.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.green)
                .symbolEffect(.pulse, options: .repeating, isActive: true)
            
            VStack(spacing: 12) {
                Text("VIGILANT EAR")
                    .font(.largeTitle.monospaced().bold())
                    .foregroundStyle(.green)
                
                Text("Acoustic monitoring requires continuous microphone access to detect environmental anomalies.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 30)
            }
            
            Button(action: {
                microphoneManager.startCapturing()
            }) {
                Text("Enable Microphone")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green.opacity(0.8))
            .padding(.horizontal, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - SwiftData Compliant Preview
#Preview {
    do {
        // 1. Create a temporary, RAM-only database configuration for the preview
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SoundEvent.self, configurations: config)
        
        let classifier = ClassificationService()
        let coordinator = AcousticCoordinator()
        
        // 2. Inject the temporary container into the MicrophoneManager
        let manager = MicrophoneManager(
            coordinator: coordinator,
            classificationService: classifier,
            container: container
        )
        
        return PermissionRequestView()
            .environment(manager)
            .environment(classifier)
        
    } catch {
        // Fallback in case the in-memory database fails to build
        return Text("Failed to load preview: \(error.localizedDescription)")
            .foregroundStyle(.red)
    }
}
