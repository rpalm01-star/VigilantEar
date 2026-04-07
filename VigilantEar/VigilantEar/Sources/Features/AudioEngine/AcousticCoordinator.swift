import AVFoundation
import Accelerate
import CoreMotion

final class AcousticCoordinator {
    
    private let tdoaProcessor = TDOAProcessor()
    private let fftProcessor = FFTProcessor(sampleCount: 4096)
    
    private let motionManager = CMMotionManager()
    private var currentHeading: Double = 0.0
    
    // Transient detection settings (made much more sensitive)
    private var rmsBaseline: Float = 0.01
    private var lastEventTime = Date.distantPast
    private let cooldownInterval: TimeInterval = 0.3   // shorter cooldown
    
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
        
        // Debug print — copy/paste a few lines from the console when you test
        //print("🎤 RMS: \(String(format: "%.4f", rms)) | Baseline: \(String(format: "%.4f", rmsBaseline)) | Transient: \(isTransient)")
        
        guard isTransient else {
            return nil  // ignore background noise
        }
        
        lastEventTime = Date()
        
        // 4. Create a new dot for this sharp event
        let phoneRelativeAngle = tdoaProcessor.calculateAngleFromSamples(samples, sampleRate: sampleRate)
        let worldAngle = phoneRelativeAngle + currentHeading
        
        let currentFreq = fftProcessor.analyze(samples: samples, sampleRate: sampleRate)
        let decibels = 20 * log10(max(Double(rms), 0.000001))
        let proximity = max(0.0, min(1.0, 1.0 - (decibels + 100) / 100))
        
        return SoundEvent(
            timestamp: Date(),
            classification: classification,
            confidence: Float(confidence),
            angle: worldAngle,
            proximity: proximity,
            decibels: Float(decibels),
            frequency: currentFreq
        )
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
