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
        
        // 🚦 THE GATE: Use our global floor (0.20).
        // We MUST let low-confidence stuff through so the pipeline can do "Ghost Tracking"!
        let validHits = classificationResult.classifications.filter { $0.confidence > AppGlobals.ML.absoluteMinimumConfidence }
        if validHits.isEmpty { return }
        
        Task { @MainActor in
            self.processClassifications(validHits)
        }
    }
    
    @MainActor
    private func processClassifications(_ classifications: [SNClassification]) {
        var collapsedHits: [String: (profile: SoundProfile, confidence: Double)] = [:]
        
        // 1. Collapse the shrapnel into canonical buckets
        for classification in classifications {
            let profile = SoundProfile.classify(classification.identifier)
            
            if profile.category == .ignored { continue }
            
            let canonLabel = profile.canonicalLabel
            let conf = classification.confidence
            
            if let existing = collapsedHits[canonLabel] {
                // Keep the highest confidence reading for this specific bucket
                if conf > existing.confidence {
                    collapsedHits[canonLabel] = (profile, conf)
                }
            } else {
                collapsedHits[canonLabel] = (profile, conf)
            }
        }
        
        let now = Date()
        
        // 2. Dispatch to the Pipeline
        for (canonLabel, data) in collapsedHits {
            let profile = data.profile
            let conf = data.confidence
            
            // 🎵 Shazam Trigger (Using the new global threshold)
            if profile.isMusic && conf >= AppGlobals.ML.shazamTriggerThreshold {
                Task { await pipeline?.startShazamAccumulation() }
            }
            
            let timeSinceLast = now.timeIntervalSince(debounceMap[canonLabel] ?? .distantPast)
            
            // 🛑 BASIC SPAM FILTER
            // We just ensure we aren't flooding the pipeline faster than the profile's cooldown allows.
            // The pipeline will handle the complex leadInTime and tailMemory math per-spatial-object!
            if timeSinceLast > profile.cooldown {
                debounceMap[canonLabel] = now
                Task {
                    await pipeline?.confirmThreatAndTrack(label: canonLabel, confidence: conf)
                }
            }
        }
        
        // Housekeeping: Clean up the map so it doesn't leak memory if sounds disappear forever
        debounceMap = debounceMap.filter { now.timeIntervalSince($0.value) < 60.0 }
    }
}
