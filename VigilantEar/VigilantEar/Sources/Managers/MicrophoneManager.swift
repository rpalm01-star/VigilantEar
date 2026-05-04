import Combine
import UIKit
import Foundation
import AVFoundation
import CoreLocation
import Observation

@Observable @MainActor
class MicrophoneManager: NSObject {
    
    // MARK: - Public State
    var currentHeading: Double = 0.0
    var currentLocation: CLLocation? = nil
    var activeMicCount: Int = 0
    var micWarning: String? = nil
    var latestDetection: String? = nil
    
    public var isListening: Bool { isRunning }
    
    // MARK: - Private State
    private var isRunning = false
    private var tapInstalled = false
    private var isProcessing = false
    private var lastProcessTime: Date = .distantPast
    
    // Throttling State
    private var lastLocationPush: Date = .distantPast
    private var lastHeadingPush: Date = .distantPast
    private let headingThreshold: Double = 1.5 // Degrees
    
    // Managers & Services
    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    private let audioWorkQueue = DispatchQueue(label: "com.vigilantear.audioProcessing", qos: .userInitiated)
    
    private let acousticPipeline: AcousticProcessingPipeline
    private let acousticCoordinator: AcousticCoordinator
    private let classificationService: ClassificationService
    private let capAlertManager: CAPAlertManager
    public let roadManager: RoadManager
    
    // MARK: - Initialization
    init(acousticCoordinator: AcousticCoordinator,
         classificationService: ClassificationService,
         roadManager: RoadManager,
         acousticPipeline: AcousticProcessingPipeline,
         capAlertManager: CAPAlertManager) {
        
        self.acousticCoordinator = acousticCoordinator
        self.classificationService = classificationService
        self.roadManager = roadManager
        self.acousticPipeline = acousticPipeline
        self.capAlertManager = capAlertManager
        super.init()
        
        configureLocationServices()
        registerOrientationObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        Task { @MainActor in
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }
    
    private func configureLocationServices() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = AppGlobals.locationDistanceFilter
        locationManager.headingFilter = AppGlobals.headingFilterDegrees
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.allowsBackgroundLocationUpdates = false
        
        locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - Audio Control
    func startCapturing() {
        guard !isRunning else { return }
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            
            applyHardwareConfiguration(session: session)
            
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            if session.maximumInputNumberOfChannels >= 2 {
                try session.setPreferredInputNumberOfChannels(2)
            }
            
            // Standard 0.5s settle time
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.installAudioTap()
            }
            
            isRunning = true
            AppGlobals.doLog(message: "Audio Flow Started", step: "MICMGR")
        } catch {
            AppGlobals.doLog(message: "Session Error: \(error.localizedDescription)", step: "MICMGR")
        }
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
            AppGlobals.doLog(message: "Hardware Configuration Warning: \(error.localizedDescription)", step: "MICMGR")
        }
    }
    
    private func installAudioTap() {
        let inputNode = audioEngine.inputNode
        if tapInstalled { inputNode.removeTap(onBus: 0) }
        
        let format = inputNode.inputFormat(forBus: 0)
        
        // 1. Safely push the hardware channel count to the UI thread
        let channelCount = Int(format.channelCount)
        Task { @MainActor in
            self.activeMicCount = channelCount
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // ✅ REPLACE WITH THIS:
            guard let bufferCopy = buffer.deepCopy() else {
                self.isProcessing = false
                return
            }
                        
            // 3. Offload to serial queue to get off the high-priority tap thread immediately
            self.audioWorkQueue.async {
                
                // 4. Hop to MainActor to check our isolated state variables safely
                Task { @MainActor in
                    
                    // The "Serial Guard" to prevent the beachball
                    guard !self.isProcessing else { return }
                    
                    self.isProcessing = true
                    
                    // 5. Send the heavy math to a detached background thread
                    Task.detached(priority: .userInitiated) {
                        await self.acousticPipeline.processAudio(buffer: bufferCopy, time: time)
                        
                        // 6. Release the gate
                        await MainActor.run { self.isProcessing = false }
                    }
                }
            }
        }
        
        tapInstalled = true
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            // 7. Silent fail setup - fixes the "complaining about a try" error
            Task { try? await self.acousticPipeline.setupAnalyzer(format: format) }
            
        } catch {
            AppGlobals.doLog(message: "Engine Failure: \(error.localizedDescription)", step: "MICMGR")
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
    
    private func registerOrientationObserver() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in }
    }
    
    @objc private func handleOrientationChange() { }
    
    // MARK: - Verification Helpers
    func verifyStereoCapability() async -> (status: VerificationStatus, reason: String?) {
        let session = AVAudioSession.sharedInstance()
        guard let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            return (.failed, "Mic not found")
        }
        let hasStereo = mic.dataSources?.contains { $0.supportedPolarPatterns?.contains(.stereo) ?? false } ?? false
        return hasStereo ? (.passed, nil) : (.failed, "Stereo unsupported")
    }
    
    func verifyAudioRouting() async -> (status: VerificationStatus, reason: String?) {
        let route = AVAudioSession.sharedInstance().currentRoute
        let invalid = route.inputs.contains { [.bluetoothHFP, .headsetMic, .carAudio].contains($0.portType) }
        return invalid ? (.failed, "Disconnect external audio") : (.passed, nil)
    }
}

// MARK: - CLLocationManagerDelegate
extension MicrophoneManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Energy Optimization: Only push location state at a controlled interval
        if Date().timeIntervalSince(lastLocationPush) >= AppGlobals.locationUpdateThrottle {
            lastLocationPush = Date()
            
            // Process road and weather logic only when location state is pushed
            roadManager.processLocationUpdate(location)
            self.currentLocation = location
            
            Task {
                await acousticPipeline.updateLocation(location.coordinate)
                capAlertManager.updateLocation(location.coordinate)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
        // Energy Optimization: Only update heading if the movement is significant
        let delta = abs(self.currentHeading - heading)
        let isSignificant = delta > headingThreshold
        let isExpired = Date().timeIntervalSince(lastHeadingPush) > 2.0
        
        if isSignificant || isExpired {
            lastHeadingPush = Date()
            self.currentHeading = heading
            Task {
                await acousticPipeline.updateHeading(heading)
            }
        }
    }
}

extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: self.frameCapacity) else { return nil }
        copy.frameLength = self.frameLength
        
        guard let src = self.floatChannelData,
              let dst = copy.floatChannelData else { return nil }
        
        let channelCount = Int(self.format.channelCount)
        let byteSize = Int(self.frameLength) * MemoryLayout<Float>.size
        
        // Physically copy the sound data into the new memory bucket
        for i in 0..<channelCount {
            memcpy(dst[i], src[i], byteSize)
        }
        return copy
    }
}
