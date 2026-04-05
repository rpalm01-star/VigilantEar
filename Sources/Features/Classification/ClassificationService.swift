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
            // Apple's built-in sound classifier (works on iOS 18+)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            self.request = request
            
            try analyzer.add(request, withObserver: self)
            print("✅ SoundAnalysis classifier loaded successfully")
        } catch {
            print("❌ Failed to load sound classifier: \(error.localizedDescription)")
        }
    }
    
    /// Call this every time MicrophoneManager gives us a new audio buffer
    func analyzeAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        do {
            try analyzer.analyze(buffer, atAudioTime: time)
        } catch {
            print("Classification analysis error: \(error.localizedDescription)")
        }
    }
}

// MARK: - SNResultsObserving
extension ClassificationService: SNResultsObserving {
    
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult,
              let top = classificationResult.classifications.first else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.currentClassification = top.identifier
            self?.confidence = top.confidence
        }
    }
    
    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("Sound classification failed: \(error.localizedDescription)")
    }
    
    func requestDidComplete(_ request: SNRequest) {
        // Not used for live streaming
    }
}
