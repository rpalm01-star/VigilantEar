@preconcurrency import AVFoundation
import Foundation

@Observable
final class MicrophoneManager {
    
    private let engine = AVAudioEngine()
    var coordinator: AcousticCoordinator?
    var lastEvent: SoundEvent?
    
    func startCapturing() {
        guard let coordinator = coordinator else { return }
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            DispatchQueue.global(qos: .userInteractive).async {
                let event = coordinator.processBuffer(buffer, at: time)
                Task { @MainActor in
                    self.lastEvent = event
                }
            }
        }
        
        try? engine.start()
        print("✅ Microphone started")
    }
}
