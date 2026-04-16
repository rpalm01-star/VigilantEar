import Foundation

final class DependencyContainer {
    static let shared = DependencyContainer()
    
    let classificationService: ClassificationService
    let microphoneManager: MicrophoneManager
    let acousticCoordinator: AcousticCoordinator
    
    private init() {
        let coordinator = AcousticCoordinator()
        let classifier = ClassificationService()
        
        self.classificationService = classifier
        self.acousticCoordinator = coordinator
        
        // SwiftData container injection is completely removed!
        self.microphoneManager = MicrophoneManager(
            coordinator: coordinator,
            classificationService: classifier
        )
    }
}
