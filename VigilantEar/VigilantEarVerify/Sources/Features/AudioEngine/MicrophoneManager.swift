import Combine
import AVFoundation

final class MicrophoneManager: ObservableObject {
    @Published var events: [SoundEvent] = []
    
    private let coordinator: AcousticCoordinator
    private let classificationService: ClassificationService
    
    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false
    private var isRunning = false
    
    init(coordinator: AcousticCoordinator,
         classificationService: ClassificationService) {
        self.coordinator = coordinator
        self.classificationService = classificationService
    }
    
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
                    // Only add a new dot when the coordinator detects a sharp sound
                    if let newEvent = self.coordinator.processFromSamples(
                        samples,
                        sampleRate: sampleRate,
                        classification: "Analyzing...",
                        confidence: 0.0
                    ) {
                        self.events.append(newEvent)
                        
                        // Keep only the 8 most recent dots
                        if self.events.count > 8 {
                            self.events.removeFirst()
                        }
                    }
                    
                    // Automatically remove dots older than 2.5 seconds
                    let now = Date()
                    self.events.removeAll { event in
                        now.timeIntervalSince(event.timestamp) > 2.5
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
