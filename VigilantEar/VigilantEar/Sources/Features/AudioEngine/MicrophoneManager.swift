import Combine
import Foundation
import AVFoundation
import CoreLocation

final class MicrophoneManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Published Properties
    @Published var events: [SoundEvent] = []
    @Published var isTestMode: Bool = false
    @Published var currentHeading: Double = 0.0
    
    // MARK: - Private Properties
    private let coordinator: AcousticCoordinator
    private let classificationService: ClassificationService
    private let locationManager = CLLocationManager()
    
    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false
    private var isRunning = false
    
    // Cache for real-time events while in Test Mode
    private var realTimeEvents: [SoundEvent] = []
    
    init(coordinator: AcousticCoordinator,
         classificationService: ClassificationService) {
        self.coordinator = coordinator
        self.classificationService = classificationService
        super.init()
        setupHeading()
    }
    
    // MARK: - Compass / Heading Setup
    
    private func setupHeading() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Request permission if needed
        locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // We use magneticHeading to align with the physical world
        DispatchQueue.main.async {
            self.currentHeading = newHeading.magneticHeading
        }
    }
    
    // MARK: - Diagnostic Toggle
    
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
                let event = SoundEvent(
                    timestamp: Date(),
                    classification: "Diagnostic",
                    confidence: 1.0,
                    angle: Double.random(in: Double(range.lowerBound)...Double(range.upperBound)),
                    proximity: Double.random(in: 0.3...0.9),
                    decibels: -20.0,
                    frequency: 440.0
                )
                testDots.append(event)
            }
        }
        self.events = testDots
        print("🛠️ VigilantEar: Diagnostic Mode - 32 Points Generated")
    }
    
    // MARK: - Audio Capture
    
    func startCapturing() {
        guard !isRunning else { return }
        
        do {
            let inputNode = audioEngine.inputNode
            let format = inputNode.inputFormat(forBus: 0)
            
            if tapInstalled {
                inputNode.removeTap(onBus: 0)
            }
            
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
                guard let self = self,
                      let channelData = buffer.floatChannelData?[0] else { return }
                
                let frameLength = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                let sampleRate = buffer.format.sampleRate
                
                Task { @MainActor in
                    if let newEvent = self.coordinator.processFromSamples(
                        samples,
                        sampleRate: sampleRate,
                        classification: "Analyzing...",
                        confidence: 0.0
                    ) {
                        self.realTimeEvents.append(newEvent)
                        if self.realTimeEvents.count > 8 {
                            self.realTimeEvents.removeFirst()
                        }
                        
                        if !self.isTestMode {
                            self.events = self.realTimeEvents
                        }
                    }
                    
                    let now = Date()
                    self.realTimeEvents.removeAll { now.timeIntervalSince($0.timestamp) > 2.5 }
                    
                    if !self.isTestMode {
                        self.events.removeAll { now.timeIntervalSince($0.timestamp) > 2.5 }
                    }
                    
                    self.classificationService.classify(buffer: samples, sampleRate: sampleRate)
                }
            }
            
            tapInstalled = true
            try audioEngine.start()
            isRunning = true
            print("✅ MicrophoneManager started successfully")
            
        } catch {
            print("Failed to start audio engine: \(error)")
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
        print("MicrophoneManager stopped")
    }
    
    deinit {
        stopCapturing()
    }
}
