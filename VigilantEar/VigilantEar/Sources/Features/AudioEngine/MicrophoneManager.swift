import Combine
import UIKit
import Foundation
import AVFoundation
import CoreLocation
import Observation

@Observable
class MicrophoneManager: NSObject, CLLocationManagerDelegate {
    
    var currentHeading: Double = 0.0
    var micWarning: String? = nil
    var latestDetection: String? = nil
    var currentLocation: CLLocation? = nil
    var activeMicCount: Int = 0
    
    public var isListening: Bool { isRunning }
    
    private var tapInstalled = false
    private var isRunning = false
    
    private let activityThresholdDB: Float = -48.0   // Tune this: -45 to -52 works well
    private var lastReportedCount: Int = 0
    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    
    private let acousticPipeline: AcousticProcessingPipeline
    private let acousticCoordinator: AcousticCoordinator
    private let classificationService: ClassificationService
    public let roadManager: RoadManager
    
    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.removeObserver(self)
        stopCapturing()
    }
    
    init(acousticCoordinator: AcousticCoordinator, classificationService: ClassificationService, roadManager: RoadManager, acousticPipeline: AcousticProcessingPipeline) {
        self.acousticCoordinator = acousticCoordinator
        self.classificationService = classificationService
        self.roadManager = roadManager
        self.acousticPipeline = acousticPipeline
        super.init()
        setupHeading()
        
        // --- THE NEW ROTATION TRACKER ---
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    private func setupHeading() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // This triggers the popup
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        // Start compass
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        
        // Start GPS
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // --- THE BRIDGE ---
        // Feed the raw hardware location straight to the network manager
        roadManager.processLocationUpdate(location)
        
        Task {
            // ALWAYS update the UI so the blue dot moves
            await MainActor.run {
                self.currentLocation = location
            }
            
            // Safely optional-chain the pipeline update
            await acousticPipeline.updateLocation(location.coordinate)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Calculate the heading before the task
        let heading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
        Task {
            // ALWAYS update the UI compass
            await MainActor.run {
                self.currentHeading = heading
            }
            
            // Safely optional-chain the pipeline update
            await acousticPipeline.updateHeading(heading)
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
            AppGlobals.doLog(message: msg, step: "MICMGR")
        } catch {
            let msg = "❌ Audio Session Critical Failure: " + error.localizedDescription
            AppGlobals.doLog(message: msg, step: "MICMGR")
        }
    }
    
    private func configureHardwareForStereo(session: AVAudioSession) {
        do {
            // --- THE FIX: ALWAYS PREFER USB-C ARRAYS IF CONNECTED ---
            if let usbInput = session.availableInputs?.first(where: { $0.portType == .usbAudio }) {
                try session.setPreferredInput(usbInput)
                try session.setPreferredInputNumberOfChannels(2)
                let msg = "🎙️ HARDWARE: External USB-C Stereo Array Connected!"
                AppGlobals.doLog(message: msg, step: "MICMGR")
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
                        try source.setPreferredPolarPattern(.stereo)
                        AppGlobals.doLog(message: "🎙️ HARDWARE: iPhone Internal Mics locked to Stereo Pattern!", step: "MICMGR")
                        break
                    }
                }
            }
            
            // --- THE MISSING LINK ---
            // Regardless of polar patterns, you MUST explicitly demand 2 channels from the session
            // Otherwise, AVAudioEngine will silently wrap it in a Mono pipeline!
            try session.setPreferredInputNumberOfChannels(2)
            
        } catch {
            AppGlobals.doLog(message: "⚠️ Hardware Stereo Config failed: " + error.localizedDescription, step: "MICMGR")
        }
    }
    
    private func startAudioTap() {
        let inputNode = audioEngine.inputNode
        if tapInstalled { inputNode.removeTap(onBus: 0) }
        
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // === LIVE ACTIVE MIC COUNTER (runs every buffer) ===
            let currentCount = self.calculateActiveMicCount(from: buffer)
            
            if currentCount != self.lastReportedCount {
                self.lastReportedCount = currentCount
                Task { @MainActor in
                    self.activeMicCount = currentCount
                }
            }
            
            // Original pipeline call
            Task {
                await self.acousticPipeline.processAudio(buffer: buffer, time: time)
            }
        }
        
        tapInstalled = true
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            let format = audioEngine.inputNode.inputFormat(forBus: 0)
            
            // Verify that we actually got stereo channels back from the hardware
            if format.channelCount < 2 {
                AppGlobals.doLog(message: "⚠️ WARNING: Audio pipeline failed to secure stereo channels. TDOA will be bypassed.", step: "MICMGR")
            }
            
            Task { try? await self.acousticPipeline.setupAnalyzer(format: format) }
            
            isRunning = true
            
            let msg = "✅ Audio Engine Flowing (Channels: \(format.channelCount))"
            AppGlobals.doLog(message: msg, step: "MICMGR")
        } catch {
            let msg = "❌ Engine Start Failed: " + error.localizedDescription
            AppGlobals.doLog(message: msg, step: "MICMGR")
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
    
    private func calculateActiveMicCount(from buffer: AVAudioPCMBuffer) -> Int {
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var activeChannels = 0
        
        for ch in 0..<channelCount {
            let samples = channelData[ch]
            
            // RMS calculation
            var sum: Float = 0.0
            for i in 0..<frameCount {
                sum += samples[i] * samples[i]
            }
            
            let rms = sqrt(sum / Float(frameCount))
            let dbFS = 20 * log10(max(rms, 1e-10))
            
            if dbFS > activityThresholdDB {
                activeChannels += 1
            }
        }
        
        return activeChannels
    }
    
    @objc private func handleOrientationChange() {
        let deviceOrientation = UIDevice.current.orientation
        
        // We need to map the physical device orientation to the specific ENUMs
        // required by the Audio Session and the Location Manager.
        let audioOrientation: AVAudioSession.StereoOrientation
        let gpsOrientation: CLDeviceOrientation
        
        switch deviceOrientation {
        case .landscapeLeft: // Notch on the LEFT
            audioOrientation = .landscapeLeft
            gpsOrientation = .landscapeLeft
        case .landscapeRight: // Notch on the RIGHT
            audioOrientation = .landscapeRight
            gpsOrientation = .landscapeRight
        case .portrait:
            audioOrientation = .portrait
            gpsOrientation = .portrait
        case .portraitUpsideDown:
            audioOrientation = .portraitUpsideDown
            gpsOrientation = .portraitUpsideDown
        default:
            // Ignore "Face Up", "Face Down", or "Unknown" states
            return
        }
        
        // 1. Re-align the Map/Radar Compass
        locationManager.headingOrientation = gpsOrientation
        
        // 2. Re-align the Acoustic DSP Array
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredInputOrientation(audioOrientation)
            
            let msg = "🔄 Hardware Array & GPS re-aligned to: \(deviceOrientation.isLandscape ? "Landscape" : "Portrait")"
            AppGlobals.doLog(message: msg, step: "MICMGR")
            
        } catch {
            let msg = "⚠️ Failed to re-align audio orientation: \(error.localizedDescription)"
            AppGlobals.doLog(message: msg, step: "MICMGR")
        }
    }
}
