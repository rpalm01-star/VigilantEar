
import Foundation

final class DependencyContainer {
    static let shared = DependencyContainer()
    static let usbMicropohone = false;
    static let dataStoreName = "VE1_detected_threats"
    
    let classificationService: ClassificationService
    let microphoneManager: MicrophoneManager
    let acousticCoordinator: AcousticCoordinator
    let pipeline: AcousticProcessingPipeline // 1. Added the property
    
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
            classificationService: classifier
        )
        
        // --- THE CRITICAL FIXES ---
        
        // 3. Plug the pipeline into the microphone manager so it gets GPS
        self.microphoneManager.pipeline = processingPipeline
        
        // 4. Tell the UI Coordinator to start listening for threats
        coordinator.startListeningToPipeline(processingPipeline)
    }
}
