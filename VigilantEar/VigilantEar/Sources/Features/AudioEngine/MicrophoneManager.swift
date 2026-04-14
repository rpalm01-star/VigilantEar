import Combine
import Foundation
import AVFoundation
import CoreLocation
import Observation
import SwiftData

@Observable
class MicrophoneManager: NSObject, CLLocationManagerDelegate {
    
    var currentHeading: Double = 0.0
    var micWarning: String? = nil
    var latestDetection: String? = nil
    
    /// Public status for UI (green listening dot)
    public var isListening: Bool { isRunning }
    
    // NEW: Public pipeline reference so the App can inject it
    public var pipeline: AcousticProcessingPipeline?
    
    private let classificationService: ClassificationService
    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    private let container: ModelContainer
    
    private var tapInstalled = false
    private var isRunning = false
    
    init(coordinator: AcousticCoordinator, classificationService: ClassificationService, container: ModelContainer) {
        self.classificationService = classificationService
        self.container = container
        super.init()
        setupHeading()
    }
    
    private func setupHeading() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.currentHeading = newHeading.magneticHeading
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
                    // We look for a source that supports the .stereo pattern
                    if source.supportedPolarPatterns?.contains(.stereo) == true {
                        try builtInMic.setPreferredDataSource(source)
                        
                        // NOTE: Even though you are in Portrait UI, we tell the mic to align
                        // as if it were Landscape to force the hardware out of 'Mono' mode.
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
            
            // --- 🕵️‍♂️ THE WIRETAP ---
            if Int.random(in: 1...30) == 1 {
                let channels = buffer.format.channelCount
                if channels >= 2, let channelData = buffer.floatChannelData {
                    let leftSample = channelData[0][500]
                    let rightSample = channelData[1][500]
                    if leftSample == rightSample {
                        print("🚨 TRAP: iOS is feeding IDENTICAL channels (Dual-Mono)")
                    } else {
                        print("✅ SUCCESS: Channels are unique (Phase separation active)")
                    }
                }
            }
            
            // Send to our new pipeline
            Task {
                await self.pipeline?.processAudio(buffer: buffer, time: time)
            }
        }
        
        tapInstalled = true
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            
            // Wake up the ML analyzer
            let format = audioEngine.inputNode.inputFormat(forBus: 0)
            Task {
                try? await self.pipeline?.setupAnalyzer(format: format)
            }
            
            isRunning = true
            print("✅ Audio Engine Flowing")
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
