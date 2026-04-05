import SwiftUI

@main
struct VigilantEarApp: App {
    
    @State private var dependencies = DependencyContainer.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.dependencies, dependencies)
                .onAppear(perform: setupServices)
        }
    }
    
    private func setupServices() {
        // Initialize all services
        let classificationService = ClassificationService()
        let microphoneManager = MicrophoneManager()
        let acousticCoordinator = AcousticCoordinator()
        
        // Inject into the shared dependency container
        dependencies.classificationService = classificationService
        dependencies.microphoneManager = microphoneManager
        dependencies.acousticCoordinator = acousticCoordinator
        
        // Start the audio pipeline
        microphoneManager.startMonitoring()
        
        print("✅ VigilantEar services initialized successfully")
    }
}
