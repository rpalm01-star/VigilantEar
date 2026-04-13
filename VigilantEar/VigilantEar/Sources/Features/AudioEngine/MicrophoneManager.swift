import Combine
import Foundation
import AVFoundation
import CoreLocation
import Accelerate
import Observation
import SwiftData

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
    private let container: ModelContainer
    
    private var tapInstalled = false
    private var isRunning = false
    private var realTimeEvents: [SoundEvent] = []
    
    init(coordinator: AcousticCoordinator, classificationService: ClassificationService, container: ModelContainer) {
        self.coordinator = coordinator
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
            // FIX: Must use .videoRecording to allow the 16 Pro Max stereo DSP to function
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
            // THE MAGIC LINE: Tell iOS to leave the Taptic Engine on!
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            configureHardwareForStereo(session: session)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startAudioTap()
            }
            print("✅ Audio Session Active (VideoRecording Mode for Spatial DSP)")
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
                        
                        // FIX: We MUST use landscape to physically align the mics Left/Right
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
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let frameLength = Int(buffer.frameLength)
            guard let channelData = buffer.floatChannelData else { return }
            
            // --- 🕵️‍♂️ THE WIRETAP ---
            // We use a random number just to sample the logs so we don't crash Xcode with print statements
            if Int.random(in: 1...30) == 1 {
                let channels = buffer.format.channelCount
                if channels == 1 {
                    print("🚨 TRAP: iOS forced 1 Channel (Mono Fallback triggered)")
                } else if channels >= 2 {
                    // Check if Apple's DSP is perfectly copying Left to Right
                    let leftSample = channelData[0][500]
                    let rightSample = channelData[1][500]
                    if leftSample == rightSample {
                        print("🚨 TRAP: iOS forced 2 Channels, but they are IDENTICAL (Dual-Mono DSP)")
                        //} else {
                        //print("✅ SUCCESS: iOS is feeding true independent Stereo channels!")
                    }
                }
            }
            // ------------------------
            
            let leftSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            // ... (rest of the tap logic continues below)
            
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
        
        // 1. Update the UI Data Source
        if let index = self.realTimeEvents.firstIndex(where: {
            $0.threatLabel == event.threatLabel && abs($0.bearing - event.bearing) < 20.0
        }) {
            self.realTimeEvents[index].bearing = event.bearing
            self.realTimeEvents[index].distance = event.distance
            
            // FIX: We must update the energy so the UI dot shrinks as the sound fades
            self.realTimeEvents[index].energy = event.energy
            
            self.realTimeEvents[index].timestamp = now
            self.realTimeEvents[index].dopplerRate = event.dopplerRate
            self.realTimeEvents[index].isApproaching = event.isApproaching
        } else {
            self.realTimeEvents.append(event)
            
            // 2. NEW: Forward new emergency events to the local database queue
            if event.isEmergency {
                // Perform the database insert on a detached background thread
                Task.detached {
                    let backgroundContext = ModelContext(self.container)
                    backgroundContext.insert(event)
                    
                    do {
                        try backgroundContext.save()
                    } catch {
                        print("❌ Failed to queue real emergency event: \(error)")
                    }
                }
            }
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
                
                // Randomize their age between 0 and 4.5 seconds old
                // so they don't all vanish at the exact same millisecond
                let randomAge = Double.random(in: 0...4.5)
                
                let event = SoundEvent(
                    timestamp: Date().addingTimeInterval(-randomAge),
                    threatLabel: "TEST",
                    bearing: Double.random(in: Double(range.lowerBound)...Double(range.upperBound)),
                    distance: Double.random(in: 0.25...0.85),
                    energy: Float.random(in: 0.4...1.0), // Boosted minimum test size
                    dopplerRate: mockDoppler,
                    isApproaching: mockDoppler > 0
                )
                testDots.append(event)
            }
        }
        
        self.events = testDots
        print("📍 Test mode: created \(testDots.count) staggered dots")
    }
    
    deinit { stopCapturing() }
}
