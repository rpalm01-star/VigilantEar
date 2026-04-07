import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var classificationService: ClassificationService
    @EnvironmentObject private var microphoneManager: MicrophoneManager // This is the name we must use [cite: 3]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                Text("VIGILANT EAR")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.green)
                
                // FIX: Use 'microphoneManager' instead of 'viewModel'
                RadarView(events: microphoneManager.events, viewModel: microphoneManager)
            }
        }
        .onAppear {
            microphoneManager.startCapturing()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ClassificationService())
        .environmentObject(MicrophoneManager(coordinator: AcousticCoordinator(), classificationService: ClassificationService()))
}
