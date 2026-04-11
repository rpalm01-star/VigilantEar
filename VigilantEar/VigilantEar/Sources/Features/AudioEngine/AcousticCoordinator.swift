import Foundation
import Accelerate
import CoreLocation

@Observable
final class AcousticCoordinator: NSObject {
    
    static let bufferSize = 4096
    
    private let tdoaProcessor = TDOAProcessor()           // temporary fallback only
    private let fftProcessor = FFTProcessor(fftSize: AcousticCoordinator.bufferSize)
    
    private let sampleRate: Double = 44100.0
    private let cooldownInterval: TimeInterval = 0.05
    private let micDistanceMeters: Double = 0.14          // ← iPhone mic spacing (calibrate later)
    
    private var lastEventTime = Date.distantPast
    private var smoothedBearing: Double?
    private var smoothedProximity: Double?
    
    // Doppler EMA baseline
    private var baselineFreq: Double = 0.0
    private let alpha: Double = 0.1
    
    // MARK: - Unified Stereo Path (preferred)
    func processStereoBuffer(
        left: [Float],
        right: [Float],
        sampleRate: Double,
        classification: String,
        currentRMS: Float
    ) -> SoundEvent? {
        
        let now = Date()
        let floor: Float = 0.01
        
        guard currentRMS > floor * 1.001,
              now.timeIntervalSince(lastEventTime) > cooldownInterval else { return nil }
        
        // === TDOA (GCC-PHAT) ===
        let tdoaResult = fftProcessor.computeTDOA(left: left, right: right, sampleRate: sampleRate)
        let phoneRelativeAngle: Double = if let (delay, _) = tdoaResult {
            asin((delay * 343.0) / micDistanceMeters) * (180.0 / .pi)
        } else {
            tdoaProcessor.calculateAngleFromSamples(left, sampleRate: sampleRate) // fallback
        }
        
        // Adaptive smoothing
        let ratio = Double(currentRMS / floor)
        let bearingSmoothing = ratio < 3.0 ? 0.95 : 0.70
        if let last = smoothedBearing {
            smoothedBearing = (last * bearingSmoothing) + (phoneRelativeAngle * (1 - bearingSmoothing))
        } else {
            smoothedBearing = phoneRelativeAngle
        }
        let finalBearing = smoothedBearing ?? phoneRelativeAngle
        
        // Proximity (logarithmic)
        let dbAboveFloor = 20 * log10(max(1.0, ratio))
        let finalProximity = min(0.95, max(0.05, 1.0 - (dbAboveFloor / 60.0)))
        
        // === DOPPLER (EMA + velocity) ===
        let (currentFreq, conf) = fftProcessor.analyze(samples: left, sampleRate: sampleRate)
        guard conf > 0.6 else {
            lastEventTime = now
            return nil
        }
        
        if abs(currentFreq - baselineFreq) < 10 {
            baselineFreq = alpha * currentFreq + (1 - alpha) * baselineFreq
        }
        
        let deltaF = currentFreq - baselineFreq
        let velocityMS = 343.0 * (deltaF / baselineFreq)
        let isApproaching = velocityMS > 0
        
        lastEventTime = now
        
        return SoundEvent(
            timestamp: now,
            threatLabel: classification,
            bearing: finalBearing,
            distance: finalProximity,
            dopplerRate: Float(velocityMS),
            isApproaching: isApproaching
        )
    }
    
    func processFromSamples(
        _ samples: [Float],
        sampleRate: Double,
        classification: String,
        confidence: Double,
        currentRMS: Float
    ) -> SoundEvent? {
        
        let now = Date()
        let floor: Float = 0.01
        
        // Only create events for meaningful sounds (ignore "Monitoring...")
        guard classification != "Monitoring..." else { return nil }
        
        guard currentRMS > floor * 0.15 else { return nil }
        guard now.timeIntervalSince(lastEventTime) > cooldownInterval else { return nil }
        
        // Mono fallback — center the dot for now
        let finalBearing: Double = 0.0
        
        let ratio = Double(currentRMS / floor)
        let finalProximity = min(0.95, max(0.05, 1.0 - (20 * log10(max(1.0, ratio)) / 60.0)))
        
        let (currentFreq, _) = fftProcessor.analyze(samples: samples, sampleRate: sampleRate)
        
        if abs(currentFreq - baselineFreq) < 10 {
            baselineFreq = alpha * currentFreq + (1 - alpha) * baselineFreq
        }
        
        let deltaF = currentFreq - baselineFreq
        let velocityMS = 343.0 * (deltaF / (baselineFreq > 0 ? baselineFreq : 440.0))
        let isApproaching = velocityMS > 0
        
        lastEventTime = now
        
        let event = SoundEvent(
            timestamp: now,
            threatLabel: classification,
            bearing: finalBearing,
            distance: finalProximity,
            dopplerRate: Float(velocityMS),
            isApproaching: isApproaching
        )
        
        print("📦 CREATED REAL EVENT → '\(classification)' @ \(String(format: "%.0f", finalBearing))° | RMS=\(String(format: "%.4f", currentRMS))")
        
        return event
    }

    func resetSmoothing() {
        smoothedBearing = nil
        smoothedProximity = nil
        baselineFreq = 0.0
    }
}
