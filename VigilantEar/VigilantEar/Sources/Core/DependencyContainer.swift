@MainActor
final class DependencyContainer {
    
    static let shared = DependencyContainer()
    
    let acousticCoordinator: AcousticCoordinator
    let classificationService: ClassificationService
    let microphoneManager: MicrophoneManager
    let roadManager: RoadManager
    let soundEventLabelManager: SoundLabelEventManager
    let acousticPipeline: AcousticProcessingPipeline
    
    // 1. Add the new manager
    let capAlertManager: CAPAlertManager
    
    init() {
        self.acousticCoordinator = AcousticCoordinator()
        self.classificationService = ClassificationService()
        self.roadManager = RoadManager()
        self.soundEventLabelManager = SoundLabelEventManager()
        
        // 2. Initialize it
        self.capAlertManager = CAPAlertManager()
        
        self.acousticPipeline = AcousticProcessingPipeline(roadManager: self.roadManager, soundEventManager: self.soundEventLabelManager)
        
        // 3. Pass it to the MicrophoneManager so it gets GPS updates
        self.microphoneManager = MicrophoneManager(
            acousticCoordinator: acousticCoordinator,
            classificationService: classificationService,
            roadManager: roadManager,
            acousticPipeline: acousticPipeline,
            capAlertManager: capAlertManager // Add this!
        )
        
        acousticCoordinator.startListeningToPipeline(acousticPipeline)
        
        // 4. Start polling in the background
        self.capAlertManager.startPolling()
    }
}
