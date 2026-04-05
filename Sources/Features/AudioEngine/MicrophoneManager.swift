import AVFoundation
import Foundation

@MainActor
final class MicrophoneManager: ObservableObject {
    private let engine = AVAudioEngine()
    private let coordinator = AcousticCoordinator()
    
    @Published var lastEvent: SoundEvent?

    func startCapturing() {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            Task { [weak self] in
                guard let self = self else { return }
                
                // Capture the coordinator locally so it can safely enter the detached task
                let localCoordinator = self.coordinator
                
                // FIX: Use .high priority to resolve the deprecation warning
                let event = await Task.detached(priority: .high) {
                    return localCoordinator.procx9ssBuffer(
                        buffer,
                        classification: "Analyzing...",
                        confidence: 0.0
                    )
                }.value
                
                self.lastEvent = event
            }
        }
        
        try? engine.start()
    }
}
