//
//  ThreatResultsObserver.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/24/26.
//

import SoundAnalysis

final class ThreatResultsObserver: NSObject, @unchecked Sendable, SNResultsObserving {
    
    private weak var pipeline: AcousticProcessingPipeline?
    
    // === DEBOUNCE STATE ===
    private var lastForwardedLabel: String = ""
    private var lastForwardedTime: Date = .distantPast
    
    nonisolated init(pipeline: AcousticProcessingPipeline) {
        self.pipeline = pipeline
        super.init()
    }
    
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        
        let topCandidates = classificationResult.classifications.prefix(5).map { ($0.identifier.lowercased(), $0.confidence) }
        
        Task { @MainActor in
            var finalLabel: String?
            var finalConfidence: Double = 0.0
            var pendingVehicleLabel: String?
            var pendingVehicleConf: Double = 0.0
            
            for (label, conf) in topCandidates {
                let profile = SoundProfile.classify(label)
                
                if profile.isEmergency && conf > 0.50 {
                    finalLabel = label
                    finalConfidence = conf
                    break
                }
                else if profile.isVehicle && conf > 0.20 && pendingVehicleLabel == nil {
                    pendingVehicleLabel = label
                    pendingVehicleConf = conf
                }
            }
            
            if finalLabel == nil {
                if let vLabel = pendingVehicleLabel {
                    finalLabel = vLabel
                    finalConfidence = pendingVehicleConf
                }
                else if let top = topCandidates.first, top.1 > 0.50 {
                    finalLabel = top.0
                    finalConfidence = top.1
                }
            }
            
            guard let detectedLabel = finalLabel else { return }
            
            // === NEW: Category-Aware Debounce ===
            let now = Date()
            let timeSinceLast = now.timeIntervalSince(self.lastForwardedTime)
            
            let profile = SoundProfile.classify(detectedLabel)
            
            let cooldown = profile.cooldown
            let shouldForward = detectedLabel != self.lastForwardedLabel || timeSinceLast > cooldown
            guard shouldForward else { return }
            
            self.lastForwardedLabel = detectedLabel
            self.lastForwardedTime = now
            
            Task {
                let profile = SoundProfile.classify(detectedLabel)
                
                if profile.isEmergency && finalConfidence < 0.50 {
                    return
                }
                
                if profile.canonicalLabel == "animal" && finalConfidence < 0.50 {
                    return;
                }
                
                if profile.canonicalLabel == "music" && finalConfidence > 0.65 {
                    await self.pipeline?.startShazamAccumulation()
                }
                
                await self.pipeline?.confirmThreatAndTrack(label: detectedLabel, confidence: finalConfidence)
            }
        }
    }
}
