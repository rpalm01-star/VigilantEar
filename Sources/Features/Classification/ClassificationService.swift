import SoundAnalysis
import AVFoundation
import Foundation

@Observable
final class ClassificationService: NSObject, SNResultsObserving {
    
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    
    var currentClassification: String = "Unknown"
    var confidence: Float = 0.0
    
    func start(with format: AVAudioFormat) {
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            self.request = request
            
            let analyzer = SNAudioStreamAnalyzer(format: format)
            self.analyzer = analyzer
            
            try analyzer.add(request, withObserver: self)
            print("✅ SoundAnalysis classifier started successfully")
        } catch {
            print("❌ Failed to start sound classifier: \(error.localizedDescription)")
        }
    }
    
    func analyzeAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let analyzer = analyzer else { return }
        
        do {
            try analyzer.analyze(buffer, atAudioFramePosition: 0)
        } catch {
            print("Classification analysis error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - SNResultsObserving
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult,
              let top = classificationResult.classifications.first else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.currentClassification = top.identifier
            self?.confidence = Float(top.confidence)
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("Sound classification failed: \(error.localizedDescription)")
    }
    
    func requestDidComplete(_ request: SNRequest) {
        // Not used for live streaming
    }
}
