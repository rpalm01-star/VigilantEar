import SwiftUI
import GoogleMaps

@main
struct VigilantEarVerifyApp: App {
    private let dependencies = DependencyContainer.shared
    
    init() {
        GMSServices.provideAPIKey("AIzaSyDbOOoFp_JqjRbAm6OsgFiOc0c9zHLjksI")  // ← put your real key here
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencies.classificationService)
                .environmentObject(dependencies.microphoneManager)
        }
    }
}
