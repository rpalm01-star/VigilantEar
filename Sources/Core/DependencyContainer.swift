import Foundation
import SwiftUI

@Observable
@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()
    
    var acousticCoordinator: AcousticCoordinator?
    var microphoneManager: MicrophoneManager?
    var permissionsManager: PermissionsManager?
    var classificationService: ClassificationService?
    
    private init() {}
}

@MainActor
struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue: DependencyContainer = .shared
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}
