import SwiftUI
import Observation

@main
struct VigilantEarApp: App {
    // These live for the entire life of the process
    @State private var permissions = PermissionsManager()
    @State private var micManager = MicrophoneManager()
    
    var body: some Scene {
        WindowGroup {
            if permissions.isMicrophoneAuthorized {
                // The "Liquid Glass" UI starts here
                ContentView(micManager: micManager)
            } else {
                // Onboarding view to request access
                PermissionRequestView(permissions: permissions)
            }
        }
    }
}
