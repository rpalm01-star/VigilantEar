import AVFoundation
import Accelerate
import CoreMotion

final class AcousticCoordinator {
    
    private let tdoaProcessor = TDOAProcessor()
    private let fftProcessor = FFTProcessor(sampleCount: 4096)
    
    private let motionManager = CMMotionManager()
    private var currentHeading: Double = 0.0
    
    // Transient detection settings
    private var rmsBaseline: Float = 0.01
    private var lastEventTime = Date.distantPast
    private let cooldownInterval: TimeInterval = 0.3
    
    // --- NEW: Doppler State Tracking ---
    // Changed to Double to match fftProcessor.analyze output
    private var previousDominantFrequency: Double?
    private var previousFrequencyTimestamp: TimeInterval?
    
    init() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let motion = motion else { return }
                self?.currentHeading = motion.attitude.yaw * (180 / .pi)
            }
        }
    }
    
    func processFromSamples(_ samples: [Float], sampleRate: Double, classification: String, confidence: Double) -> SoundEvent? {
        
        // 1. Calculate current RMS (volume)
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        
        // 2. Very slowly update background baseline
        rmsBaseline = rmsBaseline * 0.98 + rms * 0.02
        
        // 3. Much more sensitive transient detection
        let isTransient = (rms > rmsBaseline * 1.6) && (rms > 0.025) && (Date().timeIntervalSince(lastEventTime) > cooldownInterval)
        
        guard isTransient else {
            return nil  // ignore background noise
        }
        
        let currentTime = Date()
        lastEventTime = currentTime
        
        // 4. Calculate Vector with CoreMotion alignment
        let phoneRelativeAngle = tdoaProcessor.calculateAngleFromSamples(samples, sampleRate: sampleRate)
        let worldAngle = phoneRelativeAngle + currentHeading
        
        // 5. Calculate Frequency & Doppler Shift
        // currentFreq is a Double
        let currentFreq = fftProcessor.analyze(samples: samples, sampleRate: sampleRate)
        
        var dopplerRate: Float? = nil
        var isApproaching = false
        
        let currentTimestamp = currentTime.timeIntervalSince1970
        
        if let prevFreq = previousDominantFrequency, let prevTime = previousFrequencyTimestamp {
            // Keep the math in Double format to prevent the compiler errors
            let timeDelta = currentTimestamp - prevTime
            
            if timeDelta > 0 {
                let frequencyDelta = currentFreq - prevFreq
                
                // Calculate the rate and cast to Float for the SoundEvent model
                let rate = Float(frequencyDelta / timeDelta)
                dopplerRate = rate
                
                // If pitch is increasing (positive rate), it is approaching.
                if rate > 5.0 {
                    isApproaching = true
                }
            }
        }
        
        // Save state for next buffer analysis
        previousDominantFrequency = currentFreq
        previousFrequencyTimestamp = currentTimestamp
        
        // 6. Return the updated SoundEvent matching the SwiftData schema
        return SoundEvent(
            timestamp: currentTime,
            threatLabel: classification,
            bearing: worldAngle,
            dopplerRate: dopplerRate,
            isApproaching: isApproaching
            // latitude and longitude are omitted and will default to nil
        )
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
