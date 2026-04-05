import AVFoundation

class MicrophoneManager: ObservableObject {
    private let engine = AVAudioEngine()
    private let coordinator = AcousticCoordinator()
    
    @Published var lastEvent: SoundEvent?

    func startCapturing() {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // 4096 is the "Magic Number" for our FFT math
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            // Move physics to a background thread to keep the UI (Radar) smooth
            DispatchQueue.global(qos: .userInteractive).async {
                // Feed the same buffer to the live classifier
                
                let event = self.coordinator.processBuffer(buffer, classificationService?.analyzeAudioBuffer(buffer, at: time), confidence: 0.0)
                
                DispatchQueue.main.async {
                    self.lastEvent = event
                }
            }
        }
        
        try? engine.start()
    }
}
