import SoundAnalysis

final class ThreatResultsObserver: NSObject, @unchecked Sendable, SNResultsObserving {
    
    private weak var pipeline: AcousticProcessingPipeline?
    private var debounceMap: [String: Date] = [:]
    
    nonisolated init(pipeline: AcousticProcessingPipeline) {
        self.pipeline = pipeline
        super.init()
    }
    
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        
        // 1. Filter and immediately convert to a Sendable format (Tuple or Struct)
        // This "disconnects" the data from the non-sendable SNClassification objects.
        let validHits = classificationResult.classifications
            .filter { $0.confidence > AppGlobals.ML.absoluteMinimumConfidence }
            .map { (identifier: $0.identifier, confidence: $0.confidence) } // Now it's just Strings and Doubles!
        
        if validHits.isEmpty { return }
        
        Task { @MainActor in
            // 2. Pass the safe data to the processing method
            self.processSafeClassifications(validHits)
        }
    }
    
    @MainActor
    private func processSafeClassifications(_ classifications: [(identifier: String, confidence: Double)]) {
        var collapsedHits: [String: (profile: SoundProfile, confidence: Double)] = [:]
        
        for classification in classifications {
            pipeline?.sendRawLabelToHUD(classification.identifier, confidence: classification.confidence)
            
            let profile = SoundProfile.classify(classification.identifier)
            let canonicalLabel = profile.canonicalLabel
            let confidence = classification.confidence
            
            if profile.category == .ignored { continue }
            
            if let existing = collapsedHits[canonicalLabel] {
                if confidence > existing.confidence {
                    collapsedHits[canonicalLabel] = (profile, confidence)
                }
            } else {
                collapsedHits[canonicalLabel] = (profile, confidence)
            }
        }
        
        let now = Date()
        
        for (canonLabel, data) in collapsedHits {
            let dataProfile = data.profile
            let dataConfidence = data.confidence
            
            if dataProfile.isMusic && dataConfidence >= AppGlobals.ML.shazamTriggerThreshold {
                Task { await pipeline?.startShazamAccumulation() }
            }
            
            let timeSinceLast = now.timeIntervalSince(debounceMap[canonLabel] ?? .distantPast)
            
            if timeSinceLast > dataProfile.cooldown {
                debounceMap[canonLabel] = now
                Task {
                    await pipeline?.confirmThreatAndTrack(profile: dataProfile, confidence: dataConfidence)
                }
            }
        }
        
        debounceMap = debounceMap.filter { now.timeIntervalSince($0.value) < 60.0 }
    }
}
