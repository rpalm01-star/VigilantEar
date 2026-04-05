import SwiftUI
import GoogleMaps

@main
struct VigilantEarApp: App {
    @State private var dependencies = DependencyContainer.shared
    
    init() {
        GMSServices.provideAPIKey("AIzaSyDbOOoFp_JqjRbAm6OsgFiOc0c9zHLjksI")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.dependencyContainer, dependencies)   // ← THIS WAS MISSING
                .environmentObject(dependencies.classificationService)
                .environmentObject(dependencies.microphoneManager)
        }
    }
}
