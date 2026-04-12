import Foundation
import Accelerate
import CoreLocation

@Observable
final class AcousticCoordinator: NSObject {
    
    static let bufferSize = 4096
    
    private let fftProcessor = FFTProcessor(fftSize: AcousticCoordinator.bufferSize)
    
    private let sampleRate: Double = 44100.0
    private let cooldownInterval: TimeInterval = 0.05
    
    private var lastEventTime = Date.distantPast
    private var smoothedBearing: Double?
    
    private var baselineFreq: Double = 0.0
    private let alpha: Double = 0.1
    
    // City-Scale Dynamic Range
    private let floorDB: Float = -80.0
    private let ceilingDB: Float = -2.0
    
    // MARK: - Unified Stereo Path
    func processStereoBuffer(
        left: [Float],
        right: [Float],
        sampleRate: Double,
        classification: String,
        currentRMS: Float
    ) -> SoundEvent? {
        
        let now = Date()
        
        // Convert raw RMS to Decibels
        let currentDB = 20 * log10(max(currentRMS, 0.00001))
        
        guard currentDB > floorDB,
              now.timeIntervalSince(lastEventTime) > cooldownInterval else { return nil }
        
        // === 1. ILD GEOMETRY (Forced Stereo Widening) ===
        var leftRMS: Float = 0
        vDSP_rmsqv(left, 1, &leftRMS, vDSP_Length(left.count))
        
        var rightRMS: Float = 0
        vDSP_rmsqv(right, 1, &rightRMS, vDSP_Length(right.count))
        
        let totalPower = leftRMS + rightRMS
        let rawAngle: Double
        
        if totalPower > 0.0001 {
            let balance = Double((rightRMS - leftRMS) / totalPower)
            
            // Assume physical acoustic bleed caps realistic balance at +/- 0.2
            let maxPhysicalBalance = 0.2
            let clampedBalance = max(-maxPhysicalBalance, min(maxPhysicalBalance, balance))
            let normalizedBalance = clampedBalance / maxPhysicalBalance // Maps to -1.0 to 1.0
            
            // Square root curve to aggressively widen small off-center differences
            let sign = normalizedBalance < 0 ? -1.0 : 1.0
            let widenedBalance = sign * sqrt(abs(normalizedBalance))
            
            rawAngle = widenedBalance * 90.0
        } else {
            rawAngle = 0.0
        }
        
        // Adaptive smoothing based on how loud the sound is
        let linearRatio = Double((max(floorDB, min(ceilingDB, currentDB)) - floorDB) / (ceilingDB - floorDB))
        let bearingSmoothing = linearRatio < 0.5 ? 0.90 : 0.60
        
        if let last = smoothedBearing {
            smoothedBearing = (last * bearingSmoothing) + (rawAngle * (1 - bearingSmoothing))
        } else {
            smoothedBearing = rawAngle
        }
        let finalBearing = smoothedBearing ?? rawAngle
        
        // === 2. UI ENERGY & PROXIMITY (Logarithmic Curve) ===
        // Apply an exponential curve so distant/quiet sounds get more visual space on the radar
        let visualEnergy = pow(linearRatio, 0.5)
        let usableEnergyForUI = min(1.0, max(0.1, visualEnergy))
        
        // === 3. DOPPLER VELOCITY ===
        let (currentFreq, conf) = fftProcessor.analyze(samples: left, sampleRate: sampleRate)
        let velocityMS: Double
        
        if conf > 0.3 {
            if baselineFreq == 0.0 {
                baselineFreq = currentFreq
            } else if abs(currentFreq - baselineFreq) < 10 {
                baselineFreq = alpha * currentFreq + (1 - alpha) * baselineFreq
            }
            let deltaF = currentFreq - baselineFreq
            velocityMS = 343.0 * (deltaF / baselineFreq)
        } else {
            velocityMS = 0.0
        }
        
        let isApproaching = velocityMS > 0
        
        // === 4. HYBRID DISTANCE (Volume + Doppler) ===
        // Base Distance: 0.95 (edge of radar) to 0.10 (center)
        let baseRadius = 0.95 - (usableEnergyForUI * 0.85)
        
        // Doppler Modifier (scaled down so it doesn't overpower the volume proximity)
        let approachFactor = isApproaching ? (Double(velocityMS) / 100.0) : 0.0
        
        let finalProximity = max(0.05, baseRadius - approachFactor)
        
        lastEventTime = now
        
        let finalLabel = classification == "Initializing..." ? "Acoustic Event" : classification
        
        return SoundEvent(
            timestamp: now,
            threatLabel: finalLabel,
            bearing: finalBearing,
            distance: finalProximity,
            energy: Float(usableEnergyForUI),
            dopplerRate: Float(velocityMS),
            isApproaching: isApproaching
        )
    }
    
    // MARK: - Mono Fallback
    func processFromSamples(
        _ samples: [Float],
        sampleRate: Double,
        classification: String,
        confidence: Double,
        currentRMS: Float
    ) -> SoundEvent? {
        
        let now = Date()
        
        // Convert raw RMS to Decibels
        let currentDB = 20 * log10(max(currentRMS, 0.00001))
        
        // Require slightly more volume for mono processing to prevent noise triggers
        guard currentDB > floorDB + 5.0,
              now.timeIntervalSince(lastEventTime) > cooldownInterval else { return nil }
        
        let finalBearing: Double = 0.0 // Mono has no bearing
        
        // === UI ENERGY & PROXIMITY (Logarithmic Curve) ===
        let linearRatio = Double((max(floorDB, min(ceilingDB, currentDB)) - floorDB) / (ceilingDB - floorDB))
        let visualEnergy = pow(linearRatio, 0.5)
        let usableEnergyForUI = min(1.0, max(0.1, visualEnergy))
        
        // === DOPPLER VELOCITY ===
        let (currentFreq, conf) = fftProcessor.analyze(samples: samples, sampleRate: sampleRate)
        let velocityMS: Double
        
        if conf > 0.3 {
            if baselineFreq == 0.0 {
                baselineFreq = currentFreq
            } else if abs(currentFreq - baselineFreq) < 10 {
                baselineFreq = alpha * currentFreq + (1 - alpha) * baselineFreq
            }
            let deltaF = currentFreq - baselineFreq
            velocityMS = 343.0 * (deltaF / (baselineFreq > 0 ? baselineFreq : 440.0))
        } else {
            velocityMS = 0.0
        }
        
        let isApproaching = velocityMS > 0
        
        // === HYBRID DISTANCE (Volume + Doppler) ===
        let baseRadius = 0.95 - (usableEnergyForUI * 0.85)
        let approachFactor = isApproaching ? (Double(velocityMS) / 100.0) : 0.0
        let finalProximity = max(0.05, baseRadius - approachFactor)
        
        lastEventTime = now
        
        let finalLabel = classification == "Initializing..." ? "Acoustic Event" : classification
        
        return SoundEvent(
            timestamp: now,
            threatLabel: finalLabel,
            bearing: finalBearing,
            distance: finalProximity,
            energy: Float(usableEnergyForUI),
            dopplerRate: Float(velocityMS),
            isApproaching: isApproaching
        )
    }
    
    func resetSmoothing() {
        smoothedBearing = nil
        baselineFreq = 0.0
    }
}
