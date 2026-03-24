import AVFoundation
import Foundation

class AcousticEngine: NSObject {
    
    private let acousticProcessingPipeline: AcousticProcessingPipeline
    private let audioEngine = AVAudioEngine()

    // Track internal states
    private(set) var isRunning = false
    private var isProcessing = false
    private var tapInstalled = false
    
    init(acousticProcessingPipeline: AcousticProcessingPipeline) {
        AppGlobals.doLog(message: "🚀 Initialized", step: "AcousticEngine")
        self.acousticProcessingPipeline = acousticProcessingPipeline
        super.init()
    }
    
    deinit {
        AppGlobals.doLog(message: "🚀 Deinitialized", step: "AcousticEngine")
    }
    
    func start() {
        // 1. SAFETY: If we are already running, don't re-initialize the graph
        guard !isRunning else { return }
        
        // 2. CONFIGURE THE GRAPH: Install the tap BEFORE starting the engine
        // Note: Graph changes (taps) while an engine is running can cause crashes.
        AppGlobals.doLog(message: "🚀 Startup; installing tap", step: "AcousticEngine")
        installTap()
        
        do {
            // 3. PREPARE: Pre-allocates hardware resources
            audioEngine.prepare()
            
            // 4. START: The actual hardware ignition
            try audioEngine.start()
            
            self.isRunning = true
            AppGlobals.doLog(message: "🚀 AVAudioEngine started successfully", step: "AcousticEngine")
            
        } catch {
            // 5. CLEANUP: If startup fails, we must remove the tap to keep the graph clean
            self.stop()
            AppGlobals.doLog(message: "🚀 ❌ AVAudioEngine engine failed to start: \(error.localizedDescription)", step: "AcousticEngine", isError: true)
        }
    }
    
    private func installTap() {
        let inputNode = audioEngine.inputNode
        
        // Remove existing tap if present (extra safety for background resumes)
        if tapInstalled {
            inputNode.removeTap(onBus: 0)
        }
        
        let format = inputNode.inputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self = self, !self.isProcessing else { return }
            
            // Create the stable snapshot for the background task
            guard let bufferCopy = buffer.deepCopy() else { return }
            
            self.isProcessing = true
            
            Task.detached(priority: .userInitiated) {
                await self.acousticProcessingPipeline.processAudio(buffer: bufferCopy, time: time)
                // Reset the gate after the math is done
                await self.resetProcessingGate()
            }
        }
        
        tapInstalled = true
    }
    
    private func resetProcessingGate() async {
        self.isProcessing = false
    }
    
    func stop() {
        AppGlobals.doLog(message: "🚀 Stopping audio engine", step: "AcousticEngine")
        audioEngine.stop()
        if tapInstalled {
            AppGlobals.doLog(message: "🚀 Uninstalling tap", step: "AcousticEngine")
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        self.isRunning = false
    }
}

extension AVAudioPCMBuffer {
    /// Creates a physically independent copy of the audio buffer's memory.
    /// This is required to process audio on a background thread while the
    /// hardware continues to write to the original buffer.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: self.frameCapacity) else { return nil }
        copy.frameLength = self.frameLength
        
        guard let src = self.floatChannelData,
              let dst = copy.floatChannelData else { return nil }
        
        let channelCount = Int(self.format.channelCount)
        let byteSize = Int(self.frameLength) * MemoryLayout<Float>.size
        
        // Physically copy the sound data into the new memory bucket
        for i in 0..<channelCount {
            memcpy(dst[i], src[i], byteSize)
        }
        return copy
    }
}
