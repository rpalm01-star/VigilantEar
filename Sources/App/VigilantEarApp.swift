import SwiftUI

@main
struct VigilantEarApp: App {
    // Initialize the container on the Main Actor
    @State private var dependencies = DependencyContainer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                // FIX: Inject using the correct KeyPath to resolve naming mismatches
                .environment(\.dependencyContainer, dependencies)
        }
    }
}
