
import Foundation

final class DependencyContainer {
    
    static let shared = DependencyContainer()
    
    let classificationService: ClassificationService
    let microphoneManager: MicrophoneManager
    let acousticCoordinator: AcousticCoordinator
    let pipeline: AcousticProcessingPipeline
    
    private init() {
        let coordinator = AcousticCoordinator()
        let classifier = ClassificationService()
        
        // 2. Instantiate the math engine
        let processingPipeline = AcousticProcessingPipeline()
        
        self.classificationService = classifier
        self.acousticCoordinator = coordinator
        self.pipeline = processingPipeline
        
        self.microphoneManager = MicrophoneManager(
            coordinator: coordinator,
            classificationService: classifier,
        )
        
        // Plug the pipeline into the microphone manager so it gets GPS
        self.microphoneManager.pipeline = processingPipeline
        
        // Tell the UI Coordinator to start listening for threats
        coordinator.startListeningToPipeline(processingPipeline)
    }
}
