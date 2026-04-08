import Combine
import Foundation
import AVFoundation
import CoreLocation
import Accelerate

final class MicrophoneManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    // MARK: - Published Properties
    @Published var events: [SoundEvent] = []
    @Published var isTestMode: Bool = false
    @Published var currentHeading: Double = 0.0
    @Published var micWarning: String? = nil
    
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
        DispatchQueue.main.async { self.currentHeading = newHeading.magneticHeading }
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
    
    // MARK: - Audio Capture (STEREO ARRAY CONFIGURATION)
    func startCapturing() {
        guard !isRunning else { return }
        
        do {
            let session = AVAudioSession.sharedInstance()
            
            // 1. Set Category and Mode
            try session.setCategory(.playAndRecord,
                                    mode: .videoRecording,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            
            // 2. ACTIVATE THE SESSION EARLY!
            // We must activate the session before changing hardware routes,
            // otherwise iOS evaluates channel requests against the default mono route and throws -50.
            try session.setActive(true)
            
            print("📋 === AVAudioSession FULL DIAGNOSTICS ===")
            
            var stereoConfigured = false
            
            // 3. Locate built-in mic and configure it
            if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(builtInMic)
                
                if let dataSources = builtInMic.dataSources {
                    for source in dataSources {
                        if let supportedPatterns = source.supportedPolarPatterns,
                           supportedPatterns.contains(.stereo) {
                            
                            // 4. Switch hardware to Stereo
                            try source.setPreferredPolarPattern(.stereo)
                            try builtInMic.setPreferredDataSource(source)
                            print("✅ Selected \(source.dataSourceName) dataSource with Stereo Polar Pattern")
                            stereoConfigured = true
                            
                            // 5. Set orientation mapping
                            try session.setPreferredInputOrientation(.portrait)
                            break
                        }
                    }
                }
            }
            
            if !stereoConfigured {
                print("⚠️ Could not find a dataSource supporting the stereo polar pattern.")
            }
            
            // 6. NOW ask for 2 channels. Because the session is active and routed to a stereo source,
            // maximumInputNumberOfChannels is now 2, and this will succeed.
            if stereoConfigured {
                try session.setPreferredInputNumberOfChannels(2)
                print("✅ Successfully requested 2 input channels")
            } else {
                print("⚠️ Falling back to 1 channel request to prevent crash.")
                try session.setPreferredInputNumberOfChannels(1)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                self.startAudioTap()
            }
            
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    private func startAudioTap() {
        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        
        print("🎤 Hardware input format: \(hardwareFormat.channelCount) channels @ \(hardwareFormat.sampleRate) Hz")
        
        if tapInstalled { inputNode.removeTap(onBus: 0) }
        
        let desiredFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: desiredFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let frameLength = Int(buffer.frameLength)
            let channelCount = buffer.format.channelCount
            
            print("🔍 Tap received — channels: \(channelCount), frames: \(frameLength)")
            
            if let channelData = buffer.floatChannelData {
                let mic1Samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
                let mic2Samples = (channelCount >= 2)
                ? Array(UnsafeBufferPointer(start: channelData[1], count: frameLength))
                : mic1Samples
                
                let rms1 = self.rms(of: mic1Samples)
                let rms2 = self.rms(of: mic2Samples)
                
                print("   📊 RMS mic1 (bottom): \(String(format: "%.6f", rms1)) | mic2 (top): \(String(format: "%.6f", rms2))")
                
                DispatchQueue.main.async {
                    if rms2 < 0.0001 && rms1 > 0.01 {
                        self.micWarning = "⚠️ Top microphone still silent – only bottom mic active"
                    } else {
                        self.micWarning = nil
                    }
                }
                
                let samples = mic1Samples
                
                Task { @MainActor in
                    if let newEvent = self.coordinator.processFromSamples(
                        samples,
                        sampleRate: buffer.format.sampleRate,
                        classification: "Analyzing...",
                        confidence: 0.0
                    ) {
                        self.realTimeEvents.append(newEvent)
                        if self.realTimeEvents.count > 8 { self.realTimeEvents.removeFirst() }
                        if !self.isTestMode { self.events = self.realTimeEvents }
                    }
                    
                    let now = Date()
                    self.realTimeEvents.removeAll { now.timeIntervalSince($0.timestamp) > 2.5 }
                    if !self.isTestMode {
                        self.events.removeAll { now.timeIntervalSince($0.timestamp) > 2.5 }
                    }
                    self.classificationService.classify(buffer: samples, sampleRate: buffer.format.sampleRate)
                }
            }
        }
        
        tapInstalled = true
        try? audioEngine.start()
        isRunning = true
        print("✅ MicrophoneManager started successfully")
    }
    
    private func rms(of signal: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(signal, 1, &rms, vDSP_Length(signal.count))
        return rms
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
    
    deinit { stopCapturing() }
}
