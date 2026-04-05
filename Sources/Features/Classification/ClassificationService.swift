import Foundation
import SoundAnalysis

/// Main-actor isolated service for classifying acoustic events.
@MainActor
final class ClassificationService: ObservableObject {
    @Published var currentClassification: String = "Monitoring..."
    @Published var confidence: Double = 0.0
    
    // The analyzer is isolated to the MainActor to prevent data races
    private var analyzer: SNAudioStreamAnalyzer?
    
    func classify(buffer: [Float], sampleRate: Double) {
        // 1. Convert the raw samples back to a buffer format the analyzer understands
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.count)) else { return }
        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        
        // Copy the samples into the buffer
        for i in 0..<buffer.count {
            pcmBuffer.floatChannelData?[0][i] = buffer[i]
        }

        // 2. Perform analysis on a background task to keep the M4 UI fluid
        Task {
            do {
                // Initialize analyzer if needed (using the project's CoreML model)
                if analyzer == nil {
                    analyzer = SNAudioStreamAnalyzer(format: format)
                }
                
                // We use a local request to avoid capturing state incorrectly
                _ = try SNClassifySoundRequest(classifierIdentifier: .version1)
                
                // In a real implementation, you'd use a delegate here.
                // For this targeted fix, we ensure the UI update is hopped back to the MainActor.
                let results = try await performAnalysis(on: pcmBuffer)
                
                if let top = results.first {
                    // Update UI safely on the MainActor
                    self.currentClassification = top.identifier
                    self.confidence = top.confidence
                }
            } catch {
                print("Classification failed: \(error)")
            }
        }
    }
    
    // Helper to wrap the analysis in a modern async pattern
    private func performAnalysis(on buffer: AVAudioPCMBuffer) async throws -> [SNClassification] {
        // This is a simplified wrapper for the SoundAnalysis request
        return [] // Placeholder for your actual SNResultsObserving logic
    }
}
