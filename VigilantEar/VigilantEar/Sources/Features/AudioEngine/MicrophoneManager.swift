import Combine
import Foundation
import AVFoundation
import CoreLocation
import Accelerate
import Observation

@Observable
class MicrophoneManager: NSObject, CLLocationManagerDelegate {
    
    // MARK: - State Properties
    var events: [SoundEvent] = []
    var isTestMode: Bool = false
    var currentHeading: Double = 0.0
    var micWarning: String? = nil
    var latestDetection: String? = nil
    
    // MARK: - Private Properties
    private let coordinator: AcousticCoordinator
    private let classificationService: ClassificationService
    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    
    private var tapInstalled = false
    private var isRunning = false
    private var realTimeEvents: [SoundEvent] = []
    
    // MARK: - Initialization
    init(coordinator: AcousticCoordinator, classificationService: ClassificationService) {
        self.coordinator = coordinator
        self.classificationService = classificationService
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
    
    // MARK: - Audio Engine Control
    
    func startCapturing() {
        guard !isRunning else { return }
        
        let session = AVAudioSession.sharedInstance()
        do {
            // 1. ATOMIC SETUP: Set category and mode in a single call to prevent -50 errors.
            // We use .measurement for raw data, and .defaultToSpeaker to ensure we don't get 'phone call' volume.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            
            // 2. ACTIVATE FIRST: Hardware properties cannot be changed until the session is 'Live'.
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // 3. HARDWARE CONFIG: Now that session is active, request Stereo.
            configureHardwareForStereo(session: session)
            
            // 4. START ENGINE: Short delay to let the hardware 'settle' into stereo mode.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startAudioTap()
            }
            
            print("✅ Audio Session Active (Measurement Mode)")
        } catch {
            print("❌ Audio Session Critical Failure: \(error)")
            // If .measurement fails, the hardware might not support it; fallback to .default
            try? session.setMode(.default)
            try? session.setActive(true)
        }
    }
    
    private func configureHardwareForStereo(session: AVAudioSession) {
        guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
        
        do {
            try session.setPreferredInput(builtInMic)
            if let sources = builtInMic.dataSources {
                // Find the data source that supports Stereo (usually Front or Back mic)
                for source in sources {
                    if source.supportedPolarPatterns?.contains(.stereo) == true {
                        try source.setPreferredPolarPattern(.stereo)
                        try builtInMic.setPreferredDataSource(source)
                        // Align the L/R channels to the phone's physical portrait orientation
                        try session.setPreferredInputOrientation(.portrait)
                        break
                    }
                }
            }
            // Explicitly request 2 channels for TDOA math
            try session.setPreferredInputNumberOfChannels(2)
        } catch {
            print("⚠️ Hardware Stereo Config failed (Non-critical): \(error)")
        }
    }
    
    private func startAudioTap() {
        let inputNode = audioEngine.inputNode
        if tapInstalled { inputNode.removeTap(onBus: 0) }
        
        // FIX: Match hardware format EXACTLY to prevent -50 Error during tap installation.
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let frameLength = Int(buffer.frameLength)
            guard let channelData = buffer.floatChannelData else { return }
            
            // Extract Mic 1 (Left) samples
            let mic1Samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            let rms1 = self.calculateRMS(of: mic1Samples)
            
            // Process (Background Thread)
            if let newEvent = self.coordinator.processFromSamples(
                mic1Samples,
                sampleRate: buffer.format.sampleRate,
                classification: self.classificationService.currentClassification,
                confidence: 0.0,
                currentRMS: rms1
            ) {
                // UI (Main Actor)
                Task { @MainActor in
                    self.processNewEvent(newEvent, rms1: rms1)
                }
            }
            
            self.classificationService.classify(buffer: mic1Samples, sampleRate: buffer.format.sampleRate)
        }
        
        tapInstalled = true
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRunning = true
            print("✅ Audio Engine Flowing")
        } catch {
            print("❌ Engine Start Failed: \(error)")
        }
    }
    
    @MainActor
    private func processNewEvent(_ event: SoundEvent, rms1: Float) {
        let now = Date()
        
        // Use a combination of Label and Bearing to identify a 'unique' source
        // This allows a Whistle at 10° and a Bell at 90° to be two separate dots.
        if let index = self.realTimeEvents.firstIndex(where: {
            $0.threatLabel == event.threatLabel && abs($0.bearing - event.bearing) < 20.0
        }) {
            self.realTimeEvents[index].bearing = event.bearing
            self.realTimeEvents[index].distance = event.distance
            self.realTimeEvents[index].timestamp = now
        } else {
            self.realTimeEvents.append(event)
        }
        
        // Keep dots on screen for 5 seconds of silence
        self.realTimeEvents.removeAll { now.timeIntervalSince($0.timestamp) > 5.0 }
        self.events = self.realTimeEvents
    }

    // MARK: - Utilities
    
    private func calculateRMS(of signal: [Float]) -> Float {
        var val: Float = 0
        vDSP_rmsqv(signal, 1, &val, vDSP_Length(signal.count))
        return val
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
    
    @MainActor
    func toggleTestMode() {
        isTestMode.toggle()
        if isTestMode {
            runQuadrantTest()
        } else {
            self.events = realTimeEvents
        }
    }
    
    @MainActor
    private func runQuadrantTest() {
        var testDots: [SoundEvent] = []
        let quadrants = [0...89, 90...179, 180...269, 270...359]
        for range in quadrants {
            for _ in 1...10 {
                let mockDoppler = Float.random(in: -15.0...15.0)
                let event = SoundEvent(
                    timestamp: Date(),
                    threatLabel: "Diagnostic",
                    bearing: Double.random(in: Double(range.lowerBound)...Double(range.upperBound)),
                    distance: Double.random(in: 0.1...0.9),
                    dopplerRate: mockDoppler,
                    isApproaching: mockDoppler > 0
                )
                testDots.append(event)
            }
        }
        self.events = testDots
    }
    
    deinit { stopCapturing() }
}
