import SwiftUI
import GoogleMaps

@main
struct VigilantEarApp: App {
    
    // 1. Declare these as top-level properties so they are "in scope" for the body
    @State private var audioManager: MicrophoneManager
    @State private var isVerified = false
    
    // We grab this from your shared DependencyContainer
    private let classificationService = DependencyContainer.shared.classificationService
    
    init() {
        // 2. Initialize the manager using the shared dependencies
        let manager = MicrophoneManager(
            coordinator: DependencyContainer.shared.acousticCoordinator,
            classificationService: DependencyContainer.shared.classificationService
        )
        
        // This is the special syntax required to initialize a @State variable in init
        _audioManager = State(initialValue: manager)
        
        // 3. Google Maps Setup
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String, !apiKey.isEmpty {
            GMSServices.provideAPIKey(apiKey)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if isVerified {
                ContentView()
                    // Now both variables are in scope and valid!
                    .environment(audioManager)
                    .environment(classificationService)
            } else {
                StartupVerificationView {
                    withAnimation {
                        isVerified = true
                    }
                }
            }
        }
    }
}
