import Combine
import UIKit
import Foundation
import AVFoundation
import CoreLocation
import Observation

/// MicrophoneManager acts as the UI-facing coordinator for audio and spatial state.
/// It is strictly MainActor-isolated to safely drive SwiftUI updates.
@Observable @MainActor
class MicrophoneManager: NSObject {
        
    // MARK: - Dependencies
    private let acousticEngine: AcousticEngine
    private let acousticProcessingPipeline: AcousticProcessingPipeline
    private let capAlertManager: CAPAlertManager
    private let roadManager: RoadManager
    private let locationManager = CLLocationManager()

    // MARK: - Public UI State
    var currentHeading: Double = 0.0
    var currentLocation: CLLocation? = nil
    var activeMicCount: Int = 0
    var isListening: Bool { acousticEngine.isRunning }
    var isCapturing: Bool = false
    
    // MARK: - Throttling State
    private var lastLocationPush: Date = .distantPast
    private var lastHeadingPush: Date = .distantPast
    private let headingThreshold: Double = 20.0
    
    // MARK: - Initialization
    init(acousticProcessingPipeline: AcousticProcessingPipeline, capAlertManager: CAPAlertManager, roadManager: RoadManager, acousticEngine: AcousticEngine) {
        self.acousticProcessingPipeline = acousticProcessingPipeline
        self.capAlertManager = capAlertManager
        self.roadManager = roadManager
        self.acousticEngine = acousticEngine

        super.init()
        
        configureLocationServices()
        setupInterruptionObserver()
        registerOrientationObserver()
    }
    
    // MARK: - Audio Control
    func startCapturing() {
        // Use the engine's status to prevent double-starts
        guard !isListening else { return }
        guard !isCapturing else { return }
        
        isCapturing = true
        let session = AVAudioSession.sharedInstance()
        do {
            // --- ORIGINAL HARDWARE CONFIGURATION (DO NOT CHANGE) ---
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            
            applyHardwareConfiguration(session: session)
            
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            if session.maximumInputNumberOfChannels >= 2 {
                try session.setPreferredInputNumberOfChannels(2)
            }
            
            // Standard 0.5s settle time
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                // FIX: Delegate the tap installation and hardware start to the engine
                self?.acousticEngine.start()
                
                // Sync the channel count back to the UI
                self?.activeMicCount = Int(session.inputNumberOfChannels)
            }
        } catch {
            AppGlobals.doLog(message: "❌ Session Error: \(error.localizedDescription)", step: "MICMGR")
        }
        isCapturing = false
    }
    
    private func applyHardwareConfiguration(session: AVAudioSession) {
        do {
            if let usbInput = session.availableInputs?.first(where: { $0.portType == .usbAudio }) {
                try session.setPreferredInput(usbInput)
                return
            }
            
            guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
            try session.setPreferredInput(builtInMic)
            
            if let sources = builtInMic.dataSources {
                for source in sources {
                    if source.supportedPolarPatterns?.contains(.stereo) == true {
                        try builtInMic.setPreferredDataSource(source)
                        try source.setPreferredPolarPattern(.stereo)
                        break
                    }
                }
            }
        } catch {
            AppGlobals.doLog(message: "⚠️ Hardware Configuration Warning: \(error.localizedDescription)", step: "MICMGR")
        }
    }
    
    func stopCapturing() {
        guard isListening else { return }
        acousticEngine.stop()
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self.activeMicCount = 0
        } catch {
            AppGlobals.doLog(message: "🔊 Error stopping session: \(error)", step: "MicrophoneManager")
        }
    }
        
    // MARK: - Lifecycle & Observers
    
    private func setupInterruptionObserver() {
        AppGlobals.doLog(message: "🔊 Setting up interruption observer", step: "MicrophoneManager")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        AppGlobals.doLog(message: "🔊 Handling audio interruption of type: \(type)", step: "MicrophoneManager")
        switch type {
        case .began:
            AppGlobals.doLog(message: "🔊 Audio Interrupted (Phone call/System).", step: "MicrophoneManager")
            // The engine handles its own internal stop, but we update the UI flag
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                AppGlobals.doLog(message: "🔊 Interruption ended. Resuming...", step: "MicrophoneManager")
                startCapturing()
            }
        @unknown default:
            break
        }
    }
    
    private func configureLocationServices() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = AppGlobals.locationDistanceFilter
        locationManager.headingFilter = AppGlobals.headingFilterDegrees
        locationManager.pausesLocationUpdatesAutomatically = true
        
        locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        locationManager.startUpdatingLocation()
    }
    
    private func registerOrientationObserver() {
        AppGlobals.doLog(message: "🔊 Registering orientation observer", step: "MicrophoneManager")
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in }
    }
    
    @objc private func handleOrientationChange() { }
    
    func verifyStereoCapability() async -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        AppGlobals.doLog(message: "🔊 Verifying microphone stereo capability", step: "MicrophoneManager")
        let session = AVAudioSession.sharedInstance()
        guard let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            return (.failed, AppGlobals.micNotFound)
        }
        let hasStereo = mic.dataSources?.contains { $0.supportedPolarPatterns?.contains(.stereo) ?? false } ?? false
        return hasStereo ? (.passed, nil) : (.failed, AppGlobals.stereoUnsupported)
    }
    
    func verifyAudioRouting() async -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        AppGlobals.doLog(message: "🔊 Verifying microphone audio routing", step: "MicrophoneManager")
        let route = AVAudioSession.sharedInstance().currentRoute
        let invalid = route.inputs.contains { [.bluetoothHFP, .headsetMic, .carAudio].contains($0.portType) }
        return invalid ? (.failed, AppGlobals.disconnectExternaMic) : (.passed, nil)
    }
    
}

// MARK: - CLLocationManagerDelegate
extension MicrophoneManager: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Energy Optimization: Only push location state at a controlled interval
        if Date().timeIntervalSince(lastLocationPush) >= AppGlobals.locationUpdateThrottle {
            lastLocationPush = Date()
            
            self.currentLocation = location
            roadManager.processLocationUpdate(location)
            
            // Push coordinates to the actors
            Task {
                await acousticProcessingPipeline.updateLocation(location.coordinate)
                capAlertManager.updateLocation(location.coordinate)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
        let delta = abs(self.currentHeading - heading)
        let isSignificant = delta > headingThreshold
        let isExpired = Date().timeIntervalSince(lastHeadingPush) > 10.0
        
        if isSignificant || isExpired {
            lastHeadingPush = Date()
            self.currentHeading = heading
            
            Task {
                await acousticProcessingPipeline.updateHeading(heading)
            }
        }
    }
}
