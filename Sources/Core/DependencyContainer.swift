import SwiftUI

/// Main-actor isolated dependency container for VigilantEar services.
@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()
    
    // Services are initialized on the Main Actor
    let classificationService = ClassificationService()
    let microphoneManager = MicrophoneManager()
    let acousticCoordinator = AcousticCoordinator()
    
    private init() {}
}

/// Bridge for the SwiftUI Environment.
struct DependencyContainerKey: EnvironmentKey {
    // FIX: Provide a non-isolated entry point to the MainActor singleton.
    // This resolves the "conformance crosses into main actor-isolated code" error.
    static var defaultValue: DependencyContainer {
        return MainActor.assumeIsolated { .shared }
    }
}

extension EnvironmentValues {
    var dependencyContainer: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}
