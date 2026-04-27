import Combine
import UIKit
import Foundation
import AVFoundation
import CoreLocation
import Observation

@Observable
class MicrophoneManager: NSObject, CLLocationManagerDelegate {
    
    // MARK: - Public State
    var currentHeading: Double = 0.0
    var micWarning: String? = nil
    var latestDetection: String? = nil
    var currentLocation: CLLocation? = nil
    var activeMicCount: Int = 0
    
    public var isListening: Bool { isRunning }
    
    // MARK: - Private State
    private var tapInstalled = false
    private var isRunning = false
    
    private let activityThresholdDB: Float = -48.0
    private var lastReportedCount: Int = 0
    
    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    
    private let acousticPipeline: AcousticProcessingPipeline
    private let acousticCoordinator: AcousticCoordinator
    private let classificationService: ClassificationService
    public let roadManager: RoadManager
    
    private var lastLocationPush: Date = .distantPast
    private var lastHeadingPush: Date = .distantPast
    
    // MARK: - Init / Deinit
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
        
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    // MARK: - Optimized Location + Heading (now using AppGlobals)
    private func setupHeading() {
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
    
    // MARK: - Location Delegate (uses AppGlobals throttle)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        roadManager.processLocationUpdate(location)
        
        if Date().timeIntervalSince(lastLocationPush) >= AppGlobals.locationUpdateThrottle {
            lastLocationPush = Date()
            
            Task {
                await MainActor.run { self.currentLocation = location }
                await acousticPipeline.updateLocation(location.coordinate)
            }
        }
    }
    
    // MARK: - Heading Delegate (uses AppGlobals throttle)
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
        if Date().timeIntervalSince(lastHeadingPush) >= AppGlobals.headingUpdateThrottle {
            lastHeadingPush = Date()
            
            Task {
                await MainActor.run { self.currentHeading = heading }
                await acousticPipeline.updateHeading(heading)
            }
        }
    }
    
    // MARK: - Audio Session (your cute logs preserved)
    func startCapturing() {
        guard !isRunning else { return }
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            
            configureHardwareForStereo(session: session)
            
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startAudioTap()
            }
            
            let msg = "Audio Session Active (Stereo Mode Locked)"
            AppGlobals.doLog(message: msg, step: "MICMGR")
        } catch {
            let msg = "Audio Session Critical Failure: " + error.localizedDescription
            AppGlobals.doLog(message: msg, step: "MICMGR")
        }
    }
    
    private func configureHardwareForStereo(session: AVAudioSession) {
        do {
            if let usbInput = session.availableInputs?.first(where: { $0.portType == .usbAudio }) {
                try session.setPreferredInput(usbInput)
                try session.setPreferredInputNumberOfChannels(2)
                let msg = "HARDWARE: External USB-C Stereo Array Connected!"
                AppGlobals.doLog(message: msg, step: "MICMGR")
                return
            }
            
            guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
            try session.setPreferredInput(builtInMic)
            
            if let sources = builtInMic.dataSources {
                for source in sources {
                    if source.supportedPolarPatterns?.contains(.stereo) == true {
                        try builtInMic.setPreferredDataSource(source)
                        try source.setPreferredPolarPattern(.stereo)
                        AppGlobals.doLog(message: "HARDWARE: iPhone Internal Mics locked to Stereo Pattern!", step: "MICMGR")
                        break
                    }
                }
            }
            
            try session.setPreferredInputNumberOfChannels(2)
            
        } catch {
            AppGlobals.doLog(message: "Hardware Stereo Config failed: " + error.localizedDescription, step: "MICMGR")
        }
    }
    
    private func startAudioTap() {
        let inputNode = audioEngine.inputNode
        if tapInstalled { inputNode.removeTap(onBus: 0) }
        
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            let currentCount = self.calculateActiveMicCount(from: buffer)
            if currentCount != self.lastReportedCount {
                self.lastReportedCount = currentCount
                Task { @MainActor in self.activeMicCount = currentCount }
            }
            
            Task {
                await self.acousticPipeline.processAudio(buffer: buffer, time: time)
            }
        }
        
        tapInstalled = true
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            let format = audioEngine.inputNode.inputFormat(forBus: 0)
            if format.channelCount < 2 {
                AppGlobals.doLog(message: "WARNING: Audio pipeline failed to secure stereo channels. TDOA will be bypassed.", step: "MICMGR")
            }
            
            Task { try? await self.acousticPipeline.setupAnalyzer(format: format) }
            
            isRunning = true
            let msg = "Audio Engine Flowing (Channels: \(format.channelCount))"
            AppGlobals.doLog(message: msg, step: "MICMGR")
        } catch {
            let msg = "Engine Start Failed: " + error.localizedDescription
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
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        var activeSamples = 0
        for i in 0..<frameLength {
            if abs(channelData[i]) > 0.015 { activeSamples += 1 }
        }
        if activeSamples == 0 { return 0 }
        if activeSamples < frameLength / 4 { return 1 }
        return 2
    }
    
    @objc private func handleOrientationChange() {
        // Future use
    }
}
