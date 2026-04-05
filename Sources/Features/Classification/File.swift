import SoundAnalysis
import AVFoundation
import Foundation

@Observable
final class ClassificationService {
    private let analyzer = SNAudioStreamAnalyzer()
    private var request: SNClassifySoundRequest?
    
    var currentClassification: String = "Unknown"
    var confidence: Float = 0.0
    
    init() {
        setupClassifier()
    }
    
    private func setupClassifier() {
        do {
            // Use Apple's built-in sound classifier (iOS 18+ has a good one)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            self.request = request
            
            try analyzer.add(request, withObserver: self)
            print("✅ SoundAnalysis classifier ready")
        } catch {
            print("❌ Failed to create sound classifier: \(error)")
        }
    }
    
    // Called from MicrophoneManager whenever we have new audio buffers
    func analyzeAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        do {
            try analyzer.analyze(buffer, atAudioTime: time)
        } catch {
            print("Analysis error: \(error)")
        }
    }
}

// MARK: - SNResultsObserver
extension ClassificationService: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult,
              let topClassification = result.classifications.first else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.currentClassification = topClassification.identifier
            self?.confidence = topClassification.confidence
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("Classification failed: \(error)")
    }
    
    func requestDidComplete(_ request: SNRequest) {
        // Not used for streaming
    }
}
