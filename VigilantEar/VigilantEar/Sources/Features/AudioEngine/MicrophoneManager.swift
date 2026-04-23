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
        
        // This triggers the popup
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
        
        Task {
            if pipeline == nil {
                let msg = "⚠️ ERROR: GPS received, but Pipeline is NIL!"
                print(msg)
                if AppGlobals.logToCloud {
                    // FIX: Awaited because we are already inside a Task here
                    await PerformanceLogger.shared.logTelemetry(step: "0_MIC_MGR", message: msg)
                }
            }
            await pipeline?.updateLocation(location.coordinate)
        }
        
        // Keep the blue dot moving!
        Task { @MainActor in
            self.currentLocation = location
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            // Prefer True North if the GPS has it, otherwise fallback to Magnetic North
            self.currentHeading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
    
    func startCapturing() {
        guard !isRunning else { return }
        
        let session = AVAudioSession.sharedInstance()
        do {
            // 1. Set the category first (do NOT activate yet)
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
            
            // 2. Configure hardware (MUST happen before activation so iOS respects the 2-channel request)
            configureHardwareForStereo(session: session)
            
            // 3. NOW activate the session with the hardware locked in
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startAudioTap()
            }
            
            let msg = "✅ Audio Session Active (Stereo Mode Locked)"
            print(msg)
            if AppGlobals.logToCloud {
                // FIX: Wrapped in a Task so it doesn't block the synchronous audio engine startup
                Task { await PerformanceLogger.shared.logTelemetry(step: "0_MIC_MGR", message: msg) }
            }
            
        } catch {
            let msg = "❌ Audio Session Critical Failure: " + error.localizedDescription
            print(msg)
            if AppGlobals.logToCloud {
                Task { await PerformanceLogger.shared.logTelemetry(step: "0_MIC_MGR", message: msg) }
            }
        }
    }
    
    private func configureHardwareForStereo(session: AVAudioSession) {
        do {
            // --- THE FIX: ALWAYS PREFER USB-C ARRAYS IF CONNECTED ---
            if let usbInput = session.availableInputs?.first(where: { $0.portType == .usbAudio }) {
                try session.setPreferredInput(usbInput)
                try session.setPreferredInputNumberOfChannels(2)
                let msg = "🎙️ HARDWARE: External USB-C Stereo Array Connected!"
                print(msg)
                if AppGlobals.logToCloud {
                    Task { await PerformanceLogger.shared.logTelemetry(step: "0_MIC_MGR", message: msg) }
                }
                return // Skip the built-in mic configuration entirely!
            }
            
            // --- Fallback to Internal Mics ---
            guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
            
            try session.setPreferredInput(builtInMic)
            
            if let sources = builtInMic.dataSources {
                for source in sources {
                    // Look for a mic array that supports spatial audio
                    if source.supportedPolarPatterns?.contains(.stereo) == true {
                        try builtInMic.setPreferredDataSource(source)
                        try session.setPreferredInputOrientation(.landscapeRight)
                        try source.setPreferredPolarPattern(.stereo)
                        let msg = "🎙️ HARDWARE: iPhone Internal Mics locked to Landscape Stereo!"
                        print(msg)
                        if AppGlobals.logToCloud {
                            Task { await PerformanceLogger.shared.logTelemetry(step: "0_MIC_MGR", message: msg) }
                        }
                        break
                    }
                }
            }
            
            // --- THE MISSING LINK ---
            // Regardless of polar patterns, you MUST explicitly demand 2 channels from the session
            // Otherwise, AVAudioEngine will silently wrap it in a Mono pipeline!
            try session.setPreferredInputNumberOfChannels(2)
            
        } catch {
            let msg = "⚠️ Hardware Stereo Config failed: " + error.localizedDescription
            print(msg)
            if AppGlobals.logToCloud {
                Task { await PerformanceLogger.shared.logTelemetry(step: "0_MIC_MGR", message: msg) }
            }
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
            
            // Verify that we actually got stereo channels back from the hardware
            if format.channelCount < 2 {
                let msg = "⚠️ WARNING: Audio pipeline failed to secure stereo channels. TDOA will be bypassed."
                print(msg)
                if AppGlobals.logToCloud {
                    Task { await PerformanceLogger.shared.logTelemetry(step: "0_MIC_MGR", message: msg) }
                }
            }
            
            Task { try? await self.pipeline?.setupAnalyzer(format: format) }
            
            isRunning = true
            let msg = "✅ Audio Engine Flowing (Channels: \(format.channelCount))"
            print(msg)
            if AppGlobals.logToCloud {
                Task { await PerformanceLogger.shared.logTelemetry(step: "0_MIC_MGR", message: msg) }
            }
        } catch {
            let msg = "❌ Engine Start Failed: " + error.localizedDescription
            print(msg)
            if AppGlobals.logToCloud {
                Task { await PerformanceLogger.shared.logTelemetry(step: "0_MIC_MGR", message: msg) }
            }
        }
    }
    
    func stopCapturing() {
        guard isRunning else { return }
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        isRunning = false
    }
    
    deinit { stopCapturing() }
}
