import Foundation
import SwiftData

final class DependencyContainer {
    static let shared = DependencyContainer()
    
    let classificationService: ClassificationService
    let microphoneManager: MicrophoneManager
    let acousticCoordinator: AcousticCoordinator
    
    // 1. Expose the SwiftData container so the App can attach it to the environment
    let sharedModelContainer: ModelContainer
    
    private init() {
        // 2. Initialize the database FIRST
        do {
            self.sharedModelContainer = try ModelContainer(for: SoundEvent.self)
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
        
        let coordinator = AcousticCoordinator()
        let classifier = ClassificationService()
        
        self.classificationService = classifier
        self.acousticCoordinator = coordinator
        
        // 3. Inject the container into the MicrophoneManager
        self.microphoneManager = MicrophoneManager(
            coordinator: coordinator,
            classificationService: classifier,
            container: self.sharedModelContainer
        )
    }
}
