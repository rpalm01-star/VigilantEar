import SoundAnalysis

// 🛑 Make absolutely sure there is NO @MainActor above this line
final class ThreatResultsObserver: NSObject, @unchecked Sendable, SNResultsObserving {
    
    private weak var pipeline: AcousticProcessingPipeline?
    private var debounceMap: [String: Date] = [:]
    
    // ✅ THE FIX: Explicitly nonisolated so your Actor can call it instantly
    nonisolated init(pipeline: AcousticProcessingPipeline) {
        self.pipeline = pipeline
        super.init()
    }
    
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        
        let validHits = classificationResult.classifications.filter { $0.confidence > 0.20 }
        if validHits.isEmpty { return }
        
        // Bounce to the Main thread only for the actual processing
        Task { @MainActor in
            self.processClassifications(validHits)
        }
    }
    
    @MainActor
    private func processClassifications(_ classifications: [SNClassification]) {
        // === STEP 1: CANONICAL COLLAPSE ===
        var collapsedHits: [String: (profile: SoundProfile, confidence: Double)] = [:]
        
        for classification in classifications {
            let profile = SoundProfile.classify(classification.identifier)
            if profile.category == .ignored { continue }
            
            let canonLabel = profile.canonicalLabel
            let conf = classification.confidence
            
            if let existing = collapsedHits[canonLabel] {
                if conf > existing.confidence {
                    collapsedHits[canonLabel] = (profile, conf)
                }
            } else {
                collapsedHits[canonLabel] = (profile, conf)
            }
        }
        
        let now = Date()
        
        // === STEP 2: THRESHOLD & DEBOUNCE EVALUATION ===
        for (canonLabel, data) in collapsedHits {
            let profile = data.profile
            let conf = data.confidence
            
            if profile.isEmergency && conf < 0.50 { continue }
            if profile.category == .animal && conf < 0.50 { continue }
            
            if canonLabel == "music" && conf > 0.65 {
                Task { await pipeline?.startShazamAccumulation() }
            }
            
            let timeSinceLast = now.timeIntervalSince(debounceMap[canonLabel] ?? .distantPast)
            
            if timeSinceLast > profile.cooldown {
                debounceMap[canonLabel] = now
                
                Task {
                    await pipeline?.confirmThreatAndTrack(label: canonLabel, confidence: conf)
                }
            }
        }
    }
}
