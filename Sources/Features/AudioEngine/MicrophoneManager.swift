import AVFoundation
import Foundation

@MainActor
@Observable
final class MicrophoneManager {
    
    private let engine = AVAudioEngine()
    
    // Injected from DependencyContainer
    var coordinator: AcousticCoordinator?
    
    var lastEvent: SoundEvent?   // ← no @Published needed with @Observable
    
    func startCapturing() {
        guard let coordinator = coordinator else {
            print("❌ MicrophoneManager: coordinator not injected")
            return
        }
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            DispatchQueue.global(qos: .userInteractive).async {
                let event = coordinator.processBuffer(buffer, at: time)
                
                DispatchQueue.main.async {
                    self.lastEvent = event
                }
            }
        }
        
        try? engine.start()
        print("✅ MicrophoneManager started capturing")
    }
}
