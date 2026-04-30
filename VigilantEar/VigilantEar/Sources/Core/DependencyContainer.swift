
import Foundation

@MainActor
final class DependencyContainer {
    
    static let shared = DependencyContainer()
    
    let acousticCoordinator: AcousticCoordinator
    let classificationService: ClassificationService
    let microphoneManager: MicrophoneManager
    let roadManager: RoadManager
    let soundEventLabelManager: SoundLabelEventManager
    let acousticPipeline: AcousticProcessingPipeline
    
    init() {
        
        self.acousticCoordinator = AcousticCoordinator()
        self.classificationService = ClassificationService()
        self.roadManager = RoadManager()
        self.soundEventLabelManager = SoundLabelEventManager()
        self.acousticPipeline = AcousticProcessingPipeline(roadManager: self.roadManager, soundEventManager: self.soundEventLabelManager)
        self.microphoneManager = MicrophoneManager(
            acousticCoordinator: acousticCoordinator,
            classificationService: classificationService,
            roadManager: roadManager,
            acousticPipeline: acousticPipeline
        )
        
        // Tell the UI Coordinator to start listening for threats
        acousticCoordinator.startListeningToPipeline(acousticPipeline)
    }
}
