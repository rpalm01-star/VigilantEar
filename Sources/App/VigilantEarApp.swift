import SwiftUI

@main
struct VigilantEarApp: App {
    
    @State private var dependencies = DependencyContainer.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.dependencies, dependencies)
        }
    }
    
    init() {
        let classificationService = ClassificationService()
        let microphoneManager = MicrophoneManager()
        let acousticCoordinator = AcousticCoordinator()
        
        dependencies.classificationService = classificationService
        dependencies.microphoneManager = microphoneManager
        dependencies.acousticCoordinator = acousticCoordinator
        
        // Start the audio engine (change this line if your method name is different)
        microphoneManager.startCapturing()
        
        print("✅ VigilantEar services initialized")
    }
}
