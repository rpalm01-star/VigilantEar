import SoundML
import SoundAnalysis
import os.log

@MainActor
final class DependencyContainer {
    
    static let shared = DependencyContainer()
    
    private let logger = Logger(subsystem: "com.vigilantear.app", category: "General")
    
    let acousticCoordinator: AcousticCoordinator
    let acousticPipeline: AcousticProcessingPipeline
    let capAlertManager: CAPAlertManager
    let microphoneManager: MicrophoneManager
    let roadManager: RoadManager
    let soundLabelEventManager: SoundLabelEventManager
    let soundMLAnalyzer: Analyzer
    let debugSimulationManager: DebugSimulationManager
    let notificationManager: NotificationManager
    let persistentAttributesManager: PersistentAttributesManager
    let acousticEngine: AcousticEngine
    let cloudKitLogManager: CloudKitLogManager
    
    init() {
        self.persistentAttributesManager = PersistentAttributesManager()
        self.soundMLAnalyzer = Analyzer()
        self.soundMLAnalyzer.soundGroups = SoundProfile.soundMLGroups
        self.soundLabelEventManager = SoundLabelEventManager()
        self.acousticCoordinator = AcousticCoordinator()
        self.capAlertManager = CAPAlertManager()
        self.roadManager = RoadManager()
        self.debugSimulationManager = DebugSimulationManager()
        self.notificationManager = NotificationManager()
        self.cloudKitLogManager = CloudKitLogManager()
        
        // Do these last
        self.acousticPipeline = AcousticProcessingPipeline(soundMLAnalyzer: self.soundMLAnalyzer)
        self.acousticEngine = AcousticEngine(acousticProcessingPipeline: self.acousticPipeline)
        self.microphoneManager = MicrophoneManager(acousticProcessingPipeline: self.acousticPipeline,
                                                   capAlertManager: self.capAlertManager,
                                                   roadManager: self.roadManager,
                                                   acousticEngine: self.acousticEngine)
        
        self.capAlertManager.startPolling()
        
        acousticCoordinator.startListeningToPipeline(acousticPipeline)
        if (AppGlobals.isDebugDevice) {
            dumpAllSoundLabels()
        }
    }
    
    func dumpAllSoundLabels() {
        do {
            // If using Apple's built-in sound classifier:
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let allLabels = request.knownClassifications
            logger.debug("🚨 Found \(allLabels.count) possible sound labels!")
            for label in allLabels.sorted() {
                logger.debug("\"\(label)\" = \"\";")
            }
        } catch {
            logger.error("Failed to load sound classifier: \(error)")
        }
    }
    
    public func isAnyAlertEnabled() -> Bool {
        if (isAlertEnabled(key: "alert_nws") ||
            isAlertEnabled(key: "alert_knock") ||
            isAlertEnabled(key: "alert_person") ||
            isAlertEnabled(key: "alert_alarm") ||
            isAlertEnabled(key: "alert_siren")) {
            return true
        } else {
            return false
        }
    }
    
    public func isAlertEnabled(key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

}
