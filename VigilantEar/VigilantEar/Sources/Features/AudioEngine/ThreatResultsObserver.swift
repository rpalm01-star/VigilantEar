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
        
        for classification in classifications {
            
            pipeline?.sendRawLabelToHUD(classification.identifier, confidence: classification.confidence)
            
            let profile = SoundProfile.classify(classification.identifier)
            let canonicalLabel = profile.canonicalLabel
            let confidence = classification.confidence
            if profile.category == .ignored { continue }
                        
            if let existing = collapsedHits[canonicalLabel] {
                // Keep the highest confidence reading for this specific bucket
                if confidence > existing.confidence {
                    collapsedHits[canonicalLabel] = (profile, confidence)
                }
            } else {
                collapsedHits[canonicalLabel] = (profile, confidence)
            }
            
        }
        
        let now = Date()
        
        // 2. Dispatch to the Pipeline
        for (canonLabel, data) in collapsedHits {
            
            let dataProfile = data.profile
            let dataConfidence = data.confidence
                        
            // 🎵 Shazam Trigger (Using the new global threshold)
            if dataProfile.isMusic && dataConfidence >= AppGlobals.ML.shazamTriggerThreshold {
                Task { await pipeline?.startShazamAccumulation() }
            }
            
            let timeSinceLast = now.timeIntervalSince(debounceMap[canonLabel] ?? .distantPast)
            
            // 🛑 BASIC SPAM FILTER
            // We just ensure we aren't flooding the pipeline faster than the profile's cooldown allows.
            // The pipeline will handle the complex leadInTime and tailMemory math per-spatial-object!
            if timeSinceLast > dataProfile.cooldown {
                debounceMap[canonLabel] = now
                Task {
                    await pipeline?.confirmThreatAndTrack(profile: dataProfile, confidence: dataConfidence)
                }
            }
        }
        
        // Housekeeping: Clean up the map so it doesn't leak memory if sounds disappear forever
        debounceMap = debounceMap.filter { now.timeIntervalSince($0.value) < 60.0 }
    }
}
