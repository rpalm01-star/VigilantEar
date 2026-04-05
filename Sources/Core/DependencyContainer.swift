import Foundation
import SwiftUI

@Observable
final class DependencyContainer {
    static let shared = DependencyContainer()
    
    var acousticCoordinator: AcousticCoordinator?
    var microphoneManager: MicrophoneManager?
    var permissionsManager: PermissionsManager?
    var classificationService: ClassificationService?   // ← NEW
    
    private init() {}
}

// MARK: - Environment Key
struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue: DependencyContainer = .shared
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}
