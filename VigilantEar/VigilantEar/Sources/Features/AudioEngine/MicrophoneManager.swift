import Combine
import Foundation
import AVFoundation
import CoreLocation
import Accelerate
import Observation

@Observable
class MicrophoneManager: NSObject, CLLocationManagerDelegate {
    
    var events: [SoundEvent] = []
    var isTestMode: Bool = false
    var currentHeading: Double = 0.0
    var micWarning: String? = nil
    var latestDetection: String? = nil
    
    /// Public status for UI (green listening dot)
    public var isListening: Bool { isRunning }
    
    private let coordinator: AcousticCoordinator
    private let classificationService: ClassificationService
    private let locationManager = CLLocationManager()
    private let audioEngine = AVAudioEngine()
    
    private var tapInstalled = false
    private var isRunning = false
    private var realTimeEvents: [SoundEvent] = []
    
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
    
    func startCapturing() {
        guard !isRunning else { return }
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            configureHardwareForStereo(session: session)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startAudioTap()
            }
            print("✅ Audio Session Active (Measurement Mode)")
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
                        try source.setPreferredPolarPattern(.stereo)
                        try builtInMic.setPreferredDataSource(source)
                        try session.setPreferredInputOrientation(.portrait)
                        break
                    }
                }
            }
            try session.setPreferredInputNumberOfChannels(2)
        } catch {
            print("⚠️ Hardware Stereo Config failed (non-critical): \(error)")
        }
    }
    
    private func startAudioTap() {
        let inputNode = audioEngine.inputNode
        if tapInstalled { inputNode.removeTap(onBus: 0) }
        
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let frameLength = Int(buffer.frameLength)
            guard let channelData = buffer.floatChannelData else { return }
            
            let leftSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            let rms = self.calculateRMS(of: leftSamples)
            
            // === STEREO PATH (real TDOA + Doppler) ===
            var newEvent: SoundEvent?
            if buffer.format.channelCount >= 2 {
                let rightSamples = Array(UnsafeBufferPointer(start: channelData[1], count: frameLength))
                newEvent = self.coordinator.processStereoBuffer(
                    left: leftSamples,
                    right: rightSamples,
                    sampleRate: buffer.format.sampleRate,
                    classification: self.classificationService.currentClassification,
                    currentRMS: rms
                )
            } else {
                // fallback mono
                newEvent = self.coordinator.processFromSamples(
                    leftSamples,
                    sampleRate: buffer.format.sampleRate,
                    classification: self.classificationService.currentClassification,
                    confidence: 0.0,
                    currentRMS: rms
                )
            }
            
            if let event = newEvent {
                Task { @MainActor in
                    self.processNewEvent(event, rms1: rms)
                }
            }
            
            // Classification still runs on left channel (fastest)
            self.classificationService.classify(buffer: leftSamples, sampleRate: buffer.format.sampleRate)
        }
        
        tapInstalled = true
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRunning = true
            print("✅ Audio Engine Flowing (Stereo TDOA enabled)")
        } catch {
            print("❌ Engine Start Failed: \(error)")
        }
    }
    
    @MainActor
    private func processNewEvent(_ event: SoundEvent, rms1: Float) {
        let now = Date()
        if let index = self.realTimeEvents.firstIndex(where: {
            $0.threatLabel == event.threatLabel && abs($0.bearing - event.bearing) < 20.0
        }) {
            self.realTimeEvents[index].bearing = event.bearing
            self.realTimeEvents[index].distance = event.distance
            self.realTimeEvents[index].timestamp = now
            self.realTimeEvents[index].dopplerRate = event.dopplerRate
            self.realTimeEvents[index].isApproaching = event.isApproaching
        } else {
            self.realTimeEvents.append(event)
        }
        self.realTimeEvents.removeAll { now.timeIntervalSince($0.timestamp) > 5.0 }
        self.events = self.realTimeEvents
    }
    
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
            print("✅ TEST MODE ON — \(events.count) dots")
        } else {
            // Switch back to real events only
            self.events = realTimeEvents
            print("✅ TEST MODE OFF — real events: \(realTimeEvents.count) dots")
        }
    }

    @MainActor
    private func runQuadrantTest() {
        var testDots: [SoundEvent] = []
        let quadrants = [0...89, 90...179, 180...269, 270...359]
        
        for range in quadrants {
            for _ in 1...8 {
                let mockDoppler = Float.random(in: -20.0...20.0)
                let event = SoundEvent(
                    timestamp: Date(),
                    threatLabel: "TEST",
                    bearing: Double.random(in: Double(range.lowerBound)...Double(range.upperBound)),
                    distance: Double.random(in: 0.25...0.85),
                    dopplerRate: mockDoppler,
                    isApproaching: mockDoppler > 0
                )
                testDots.append(event)
            }
        }
        
        self.events = testDots          // only temporary
        // DO NOT touch realTimeEvents here
        print("📍 Test mode: created \(testDots.count) dots")
    }
    deinit { stopCapturing() }
}
