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
            // 1. Extract the raw audio data on the current thread (Main Actor)
            // This creates a thread-safe copy of the audio samples
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            let audioSamples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            let sampleRate = buffer.format.sampleRate

            Task { [weak self] in
                guard let self = self else { return }
                let localCoordinator = self.coordinator
                
                // 2. Pass the thread-safe 'audioSamples' instead of the 'buffer' object
                let event = await Task.detached(priority: .high) {
                    return localCoordinator.processFromSamples(
                        audioSamples,
                        sampleRate: sampleRate,
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
