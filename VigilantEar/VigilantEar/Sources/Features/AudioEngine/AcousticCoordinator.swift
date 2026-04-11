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
    
    // MARK: - Unified Stereo Path
    func processStereoBuffer(
        left: [Float],
        right: [Float],
        sampleRate: Double,
        classification: String,
        currentRMS: Float
    ) -> SoundEvent? {
        
        let now = Date()
        let floor: Float = 0.005
        
        guard currentRMS > floor * 1.001,
              now.timeIntervalSince(lastEventTime) > cooldownInterval else { return nil }
        
        // === 1. ILD GEOMETRY (Apple's DSP Panning) ===
        // We calculate the independent power of the Left and Right channels
        var leftRMS: Float = 0
        vDSP_rmsqv(left, 1, &leftRMS, vDSP_Length(left.count))
        
        var rightRMS: Float = 0
        vDSP_rmsqv(right, 1, &rightRMS, vDSP_Length(right.count))
        
        let totalPower = leftRMS + rightRMS
        let rawAngle: Double
        
        if totalPower > 0.0001 {
            // Balance ranges from -1.0 (All Left) to 1.0 (All Right)
            let balance = Double((rightRMS - leftRMS) / totalPower)
            
            // Map that balance to our 180-degree radar dome (-90° to 90°)
            // We multiply by an aggressive 150.0 to counteract Apple's center-heavy DSP mixing
            rawAngle = max(-90.0, min(90.0, balance * 150.0))
        } else {
            rawAngle = 0.0
        }
        
        // Adaptive smoothing
        let energyRatio = Double(currentRMS / floor)
        let bearingSmoothing = energyRatio < 3.0 ? 0.90 : 0.60
        if let last = smoothedBearing {
            smoothedBearing = (last * bearingSmoothing) + (rawAngle * (1 - bearingSmoothing))
        } else {
            smoothedBearing = rawAngle
        }
        let finalBearing = smoothedBearing ?? rawAngle
        
        // === 2. UI ENERGY ===
        let ceiling: Float = 0.15
        let usableRMS = max(0.0, currentRMS - floor)
        let normalizedEnergy = min(1.0, max(0.2, usableRMS / ceiling))
        
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
        // 1. Base Distance: Loud sounds plot closer to the center, quiet sounds plot near the edge.
        // We use the normalizedEnergy we already calculated (0.2 to 1.0)
        // A maximum energy (1.0) plots at 0.2 radius. Minimum energy plots at 0.9 radius.
        let baseRadius = 0.9 - (Double(normalizedEnergy) * 0.7)
        
        // 2. Doppler Modifier: If the object is actually driving towards us, pull it even closer.
        let approachFactor = isApproaching ? (Double(velocityMS) / 50.0) : 0.0
        
        // Combine them, keeping a safety buffer so it doesn't cross dead-center (0.0)
        let finalProximity = max(0.05, baseRadius - approachFactor)
        
        lastEventTime = now
        
        let finalLabel = classification == "Monitoring..." ? "Acoustic Event" : classification
        
        return SoundEvent(
            timestamp: now,
            threatLabel: finalLabel,
            bearing: finalBearing,
            distance: finalProximity,
            energy: normalizedEnergy,
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
        let floor: Float = 0.005
        
        guard currentRMS > floor * 1.5 else { return nil }
        guard now.timeIntervalSince(lastEventTime) > cooldownInterval else { return nil }
        
        let finalBearing: Double = 0.0
        
        let ceiling: Float = 0.15
        let usableRMS = max(0.0, currentRMS - floor)
        let normalizedEnergy = min(1.0, max(0.2, usableRMS / ceiling))
        
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
        
        // === 4. HYBRID DISTANCE (Volume + Doppler) ===
        // 1. Base Distance: Loud sounds plot closer to the center, quiet sounds plot near the edge.
        // We use the normalizedEnergy we already calculated (0.2 to 1.0)
        // A maximum energy (1.0) plots at 0.2 radius. Minimum energy plots at 0.9 radius.
        let baseRadius = 0.9 - (Double(normalizedEnergy) * 0.7)
        
        // 2. Doppler Modifier: If the object is actually driving towards us, pull it even closer.
        let approachFactor = isApproaching ? (Double(velocityMS) / 50.0) : 0.0
        
        // Combine them, keeping a safety buffer so it doesn't cross dead-center (0.0)
        let finalProximity = max(0.05, baseRadius - approachFactor)
        
        lastEventTime = now
        
        let finalLabel = classification == "Monitoring..." ? "Acoustic Event" : classification
        
        return SoundEvent(
            timestamp: now,
            threatLabel: finalLabel,
            bearing: finalBearing,
            distance: finalProximity,
            energy: normalizedEnergy,
            dopplerRate: Float(velocityMS),
            isApproaching: isApproaching
        )
    }
    
    func resetSmoothing() {
        smoothedBearing = nil
        baselineFreq = 0.0
    }
}
