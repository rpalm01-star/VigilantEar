import SwiftUI
import GoogleMaps   // ← ADD THIS

@main
struct VigilantEarApp: App {
    // Initialize the container on the Main Actor
    @State private var dependencies = DependencyContainer.shared

    init() {
        GMSServices.provideAPIKey("AIzaSyDbOOoFp_JqjRbAm6OsgFiOc0c9zHLjksI")  // ← PASTE YOUR KEY HERE
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // FIX: Inject using the correct KeyPath to resolve naming mismatches
                .environment(\.dependencyContainer, dependencies)
        }
    }
}
