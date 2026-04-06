import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var classificationService: ClassificationService
    @EnvironmentObject private var microphoneManager: MicrophoneManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                Text("VIGILANT EAR")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.green)
                
                RadarView(events: microphoneManager.events)
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
