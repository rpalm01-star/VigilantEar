import Combine
import Foundation
import AVFoundation
import CoreLocation
import Accelerate
import Observation

@Observable
class MicrophoneManager: NSObject, CLLocationManagerDelegate {
    
    // MARK: - Published Properties
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
    
    init(coordinator: AcousticCoordinator,
         classificationService: ClassificationService) {
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
        self.currentHeading = newHeading.magneticHeading
    }
    
    @MainActor
    func toggleTestMode() {
        isTestMode.toggle()
        if isTestMode {
            runQuadrantTest()
        } else {
            self.events = realTimeEvents
            print("📡 VigilantEar: Reverted to Live Audio")
        }
    }
    
    @MainActor
    private func runQuadrantTest() {
        var testDots: [SoundEvent] = []
        let quadrants = [0...89, 90...179, 180...269, 270...359]
        for range in quadrants {
            for _ in 1...8 {
                let mockDoppler = Float.random(in: -15.0...15.0)
                let event = SoundEvent(
                    timestamp: Date(),
                    threatLabel: "Diagnostic",
                    bearing: Double.random(in: Double(range.lowerBound)...Double(range.upperBound)),
                    dopplerRate: mockDoppler,
                    isApproaching: mockDoppler > 0
                )
                testDots.append(event)
            }
        }
        self.events = testDots
    }
    
    func startCapturing() {
        guard !isRunning else { return }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .videoRecording,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            
            try session.setActive(true)
            
            var stereoConfigured = false
            
            if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(builtInMic)
                
                if let dataSources = builtInMic.dataSources {
                    for source in dataSources {
                        if let supportedPatterns = source.supportedPolarPatterns,
                           supportedPatterns.contains(.stereo) {
                            
                            try source.setPreferredPolarPattern(.stereo)
                            try builtInMic.setPreferredDataSource(source)
                            stereoConfigured = true
                            try session.setPreferredInputOrientation(.portrait)
                            break
                        }
                    }
                }
            }
            
            if stereoConfigured {
                try session.setPreferredInputNumberOfChannels(2)
            } else {
                try session.setPreferredInputNumberOfChannels(1)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.startAudioTap()
            }
            
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func startAudioTap() {
        let inputNode = audioEngine.inputNode
        
        if tapInstalled { inputNode.removeTap(onBus: 0) }
        
        let desiredFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: desiredFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let frameLength = Int(buffer.frameLength)
            let channelCount = buffer.format.channelCount
            
            if let channelData = buffer.floatChannelData {
                let mic1Samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
                let mic2Samples = (channelCount >= 2)
                ? Array(UnsafeBufferPointer(start: channelData[1], count: frameLength))
                : mic1Samples
                
                let rms1 = self.calculateRMS(of: mic1Samples)
                let rms2 = self.calculateRMS(of: mic2Samples)
                
                // Mic Health Check
                Task { @MainActor in
                    if rms2 < 0.0001 && rms1 > 0.01 {
                        self.micWarning = "⚠️ Top microphone still silent"
                    } else {
                        self.micWarning = nil
                    }
                }
                
                // Core Processing Logic
                Task { @MainActor in
                    if let newEvent = self.coordinator.processFromSamples(
                        mic1Samples,
                        sampleRate: buffer.format.sampleRate,
                        classification: self.classificationService.currentClassification,
                        confidence: 0.0
                    ) {
                        print("🎯 GATE PASSED! RMS: \(rms1)")

                        let label = newEvent.threatLabel
                        let displayRMS = rms1

                        // 1. Update live array
                        self.realTimeEvents.append(newEvent)
                        if self.realTimeEvents.count > 8 { self.realTimeEvents.removeFirst() }
                        if !self.isTestMode { self.events = self.realTimeEvents }

                        // 2. Update HUD
                        self.latestDetection = "\(label): \(String(format: "%.3f", displayRMS)) RMS"

                        // 3. Auto-clear HUD after 3 seconds
                        try? await Task.sleep(for: .seconds(3))
                        if self.latestDetection?.contains(label) == true {
                            self.latestDetection = nil
                        }
                    }
                    
                    // Housekeeping & Classification
                    let now = Date()
                    self.realTimeEvents.removeAll { now.timeIntervalSince($0.timestamp) > 2.5 }
                    if !self.isTestMode {
                        self.events.removeAll { now.timeIntervalSince($0.timestamp) > 2.5 }
                    }
                    self.classificationService.classify(buffer: mic1Samples, sampleRate: buffer.format.sampleRate)
                }
            }
        }
        
        tapInstalled = true
        try? audioEngine.start()
        isRunning = true
        print("✅ MicrophoneManager started successfully")
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
    
    deinit { stopCapturing() }
}
