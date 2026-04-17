import Combine
import Foundation
import AVFoundation
import CoreLocation
import Observation

@Observable
class MicrophoneManager: NSObject, CLLocationManagerDelegate {
    
    var currentHeading: Double = 0.0
    var micWarning: String? = nil
    var latestDetection: String? = nil
    
    /// Public status for UI (green listening dot)
    public var isListening: Bool { isRunning }
    public var pipeline: AcousticProcessingPipeline?
    
    private let coordinator: AcousticCoordinator
    private let classificationService: ClassificationService
    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    
    private var tapInstalled = false
    private var isRunning = false
    var currentLocation: CLLocation? = nil

    init(coordinator: AcousticCoordinator, classificationService: ClassificationService) {
        self.coordinator = coordinator
        self.classificationService = classificationService
        super.init()
        setupHeading()
    }
    
    private func setupHeading() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // This triggers the popup (now that the Info.plist is fixed)
        locationManager.requestWhenInUseAuthorization()
        
        // Start compass
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        
        // Start GPS
        locationManager.startUpdatingLocation()
    }
        
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // TRIPWIRE 1: Are we actually catching the GPS here, or is MapKit doing it secretly?
        //print("📍 HARDWARE: GPS ping caught by MicrophoneManager")
        
        Task {
            // TRIPWIRE 2: Is the bridge connected?
            if pipeline == nil {
                print("⚠️ ERROR: GPS received, but Pipeline is NIL!")
            }
            await pipeline?.updateLocation(location.coordinate)
        }

        // Your existing code saving the location for the UI
        Task { @MainActor in
            self.currentLocation = location
        }

    }
    
    func startCapturing() {
        guard !isRunning else { return }
        
        let session = AVAudioSession.sharedInstance()
        do {
            // 1. Restore the .videoRecording category from yesterday (it's the most stable for stereo)
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
            
            // 2. Activate the session
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // 3. Configure hardware exactly like the version that worked
            configureHardwareForStereo(session: session)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startAudioTap()
            }
            print("✅ Audio Session Active (Yesterday's Stable Mode)")
        } catch {
            print("❌ Audio Session Critical Failure: \(error)")
        }
    }
    
    private func configureHardwareForStereo(session: AVAudioSession) {
        guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
        do {
            try session.setPreferredInput(builtInMic)
            if let sources = builtInMic.dataSources {
                for source in sources {
                    if source.supportedPolarPatterns?.contains(.stereo) == true {
                        try builtInMic.setPreferredDataSource(source)
                        try session.setPreferredInputOrientation(.landscapeRight)
                        try source.setPreferredPolarPattern(.stereo)
                        break
                    }
                }
            }
            try session.setPreferredInputNumberOfChannels(2)
        } catch {
            print("⚠️ Hardware Stereo Config failed: \(error)")
        }
    }
    
    private func startAudioTap() {
        let inputNode = audioEngine.inputNode
        if tapInstalled { inputNode.removeTap(onBus: 0) }
        
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            Task {
                await self.pipeline?.processAudio(buffer: buffer, time: time)
            }
        }
        
        tapInstalled = true
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            let format = audioEngine.inputNode.inputFormat(forBus: 0)
            Task { try? await self.pipeline?.setupAnalyzer(format: format) }
            
            isRunning = true
            print("✅ Audio Engine Flowing (Stereo)")
        } catch {
            print("❌ Engine Start Failed: \(error)")
        }
    }
    
    func stopCapturing() {
        guard isRunning else { return }
        audioEngine.stop()
        locationManager.stopUpdatingHeading()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        isRunning = false
    }
    
    deinit { stopCapturing() }
}
