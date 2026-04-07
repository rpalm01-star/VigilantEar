import Combine
import Foundation
import SoundAnalysis
import CoreML

@MainActor
final class ClassificationService: ObservableObject {
    @Published var currentClassification: String = "Monitoring..."
    @Published var confidence: Double = 0.0
    
    // MARK: - Long-lived Pipeline Properties
    private var analyzer: SNAudioStreamAnalyzer?
    private let resultsObserver = ClassificationResultsObserver()
    private let clock = ContinuousClock()
    private var isPipelineReady = false
    
    func classify(buffer: [Float], sampleRate: Double) {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.count)) else { return }
        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        
        for i in 0..<buffer.count {
            pcmBuffer.floatChannelData?[0][i] = buffer[i]
        }

        Task {
            let start = clock.now
            
            // Internal do-catch inside setupPipeline handles initialization errors
            if !isPipelineReady {
                setupPipeline(format: format)
            }
            
            // This call does not throw
            analyzer?.analyze(pcmBuffer, atAudioFramePosition: 0)
            
            if let top = resultsObserver.topClassifications.first {
                self.currentClassification = top.identifier
                self.confidence = top.confidence
            }
            
            // Use our new automatic telemetry standard
            PerformanceLogger.log(label: "Neural-Engine", startTime: start, instance: self)
        }
    }
    
    private func setupPipeline(format: AVAudioFormat) {
        do {
            let newAnalyzer = SNAudioStreamAnalyzer(format: format)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            
            try newAnalyzer.add(request, withObserver: resultsObserver)
            self.analyzer = newAnalyzer
            self.isPipelineReady = true
            print("🚀 ANE Pipeline Primed and Ready")
        } catch {
            print("Failed to prime ANE: \(error)")
        }
    }
}

// MARK: - Observer Cache
class ClassificationResultsObserver: NSObject, SNResultsObserving {
    var topClassifications: [SNClassification] = []
    
    func request(_ request: SNRequest, didProduce results: SNResult) {
        guard let classificationResult = results as? SNClassificationResult else { return }
        topClassifications = classificationResult.classifications
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("Analysis request failed: \(error)")
    }
}
