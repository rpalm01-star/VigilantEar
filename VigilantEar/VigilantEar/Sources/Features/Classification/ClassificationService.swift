import Combine
import Foundation
import SoundAnalysis
import CoreML

@Observable
@MainActor
final class ClassificationService {
    var currentClassification: String = "Initializing..."
    var confidence: Double = 0.0
    
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
            PerformanceLogger.shared.start(task: "Neural-Engine")
            
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
            
            PerformanceLogger.shared.stop(task: "Neural-Engine")
        }
    }
    
    private func setupPipeline(format: AVAudioFormat) {
        do {
            let newAnalyzer = SNAudioStreamAnalyzer(format: format)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 1000)
            request.overlapFactor = 0.9 // This is the "Rapid Fire" fix
            
            try newAnalyzer.add(request, withObserver: resultsObserver)
            self.analyzer = newAnalyzer
            self.isPipelineReady = true
            PerformanceLogger.shared.start(task: "ANE Pipeline")
            let msg = "🚀 ANE Pipeline Primed and Ready"
            AppGlobals.doLog(message: msg, step: "AV_AUDIO");
        } catch {
            let msg = "🚀 ANE Pipeline failed: " + error.localizedDescription
            AppGlobals.doLog(message: msg, step: "AV_AUDIO");
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
        let msg = "⚠️ ClassificationResultsObserver analysis failed: " + error.localizedDescription
        AppGlobals.doLog(message: msg, step: "AV_AUDIO");
    }
}
