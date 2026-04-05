import SoundAnalysis
import AVFoundation
import Foundation

@Observable
final class ClassificationService: NSObject, SNResultsObserving {
    
    private var analyzer: SNAudioStreamAnalyzer?
    var currentClassification: String = "Unknown"
    var confidence: Float = 0.0
    
    func start(with format: AVAudioFormat) {
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let analyzer = SNAudioStreamAnalyzer(format: format)
            self.analyzer = analyzer
            try analyzer.add(request, withObserver: self)
            print("✅ Classifier ready")
        } catch {
            print("Classifier failed: \(error)")
        }
    }
    
    func analyzeAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let analyzer = analyzer else { return }
        try? analyzer.analyze(buffer, atAudioFramePosition: 0)
    }
    
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult,
              let top = result.classifications.first else { return }
        DispatchQueue.main.async {
            self.currentClassification = top.identifier
            self.confidence = Float(top.confidence)
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}
