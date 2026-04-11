import Foundation
import Accelerate
import CoreLocation

@Observable
final class AcousticCoordinator: NSObject {
    
    static let bufferSize = 4096
    
    private let tdoaProcessor = TDOAProcessor()
    private let fftProcessor = FFTProcessor(sampleCount: AcousticCoordinator.bufferSize)
    
    // MARK: - Constants & Calibration
    private let sampleRate: Double = 44100.0
    private let cooldownInterval: TimeInterval = 0.05 // 50ms for high-speed tracking
    
    // MARK: - State Persistence
    private var lastEventTime = Date.distantPast
    private var smoothedBearing: Double?
    private var smoothedProximity: Double?
    
    // Doppler State
    private var previousDominantFrequency: Double?
    private var previousFrequencyTimestamp: Double?
    
    // MARK: - Processing Flow
    
    func processFromSamples(
        _ samples: [Float],
        sampleRate: Double,
        classification: String,
        confidence: Double,
        currentRMS: Float
    ) -> SoundEvent? {
        
        let now = Date()
        let floor: Float = 0.01 // Your calibrated 'Sweet Spot' floor
        
        // 1. SENSITIVITY GATE: 1% above floor allows for long "tails" on whistles
        guard currentRMS > floor * 1.001 else { return nil }
        
        // 2. COOLDOWN: Prevents CPU thrashing while allowing fluid movement
        guard now.timeIntervalSince(lastEventTime) > cooldownInterval else { return nil }
        
        // --- BEARING (TDOA) ---
        let phoneRelativeAngle = tdoaProcessor.calculateAngleFromSamples(samples, sampleRate: sampleRate)
        // Note: Replace 0.0 with currentHeading if passed from Manager,
        // or add a heading property to this class.
        let worldAngle = phoneRelativeAngle
        
        // Adaptive Smoothing: If signal is weak (Ratio < 3), freeze position more strictly
        let ratio = Double(currentRMS / floor)
        let bearingSmoothing = ratio < 3.0 ? 0.95 : 0.70
        
        if let lastSmooth = smoothedBearing {
            smoothedBearing = (lastSmooth * bearingSmoothing) + (worldAngle * (1.0 - bearingSmoothing))
        } else {
            smoothedBearing = worldAngle
        }
        let finalBearing = smoothedBearing ?? worldAngle
        
        // Logarithmic distance: The more 'dB' above the floor, the closer it gets.
        // This handles a whisper and a siren in the same math.
        let dbAboveFloor = 20 * log10(max(1.0, ratio))
        let maxDbRange: Double = 60.0 // Adjust this: Lower = more sensitive, Higher = less sensitive
        let finalProximity = min(0.95, max(0.05, 1.0 - (dbAboveFloor / maxDbRange)))
        
        // --- DOPPLER (FREQUENCY SHIFT) ---
        let currentFreq = fftProcessor.analyze(samples: samples, sampleRate: sampleRate)
        var dopplerRate: Float? = nil
        var isApproaching = false
        let currentTimestamp = now.timeIntervalSince1970
        
        if let prevFreq = previousDominantFrequency, let prevTime = previousFrequencyTimestamp {
            let timeDelta = currentTimestamp - prevTime
            if timeDelta > 0 && timeDelta < 2.0 { // 2s window for frequency memory
                let frequencyDelta = currentFreq - prevFreq
                let rate = Float(frequencyDelta / timeDelta)
                dopplerRate = rate
                
                // If frequency is rising, object is approaching
                if rate > 5.0 { isApproaching = true }
            }
        }
        
        // Update Doppler State
        self.previousDominantFrequency = currentFreq
        self.previousFrequencyTimestamp = currentTimestamp
        self.lastEventTime = now
        
        // 3. GENERATE EVENT
        return SoundEvent(
            timestamp: now,
            threatLabel: classification,
            bearing: finalBearing,
            distance: finalProximity,
            dopplerRate: dopplerRate,
            isApproaching: isApproaching
        )
    }
    
    // Reset state when a sound disappears
    func resetSmoothing() {
        smoothedBearing = nil
        smoothedProximity = nil
        previousDominantFrequency = nil
        previousFrequencyTimestamp = nil
    }
}
