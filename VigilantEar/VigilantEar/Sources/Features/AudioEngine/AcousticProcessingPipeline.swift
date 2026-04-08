import AVFoundation
import Accelerate
import SoundAnalysis

// MARK: - Core Pipeline Actor
actor AcousticProcessingPipeline {
    
    private let minimumSustainTime: TimeInterval = 0.5
    private let dangerRadiusThresholdDB: Float = -40.0
    private var sustainedAudioFrames: Int = 0
    private let sampleRate: Double = 44100.0
    private let bufferSize: AVAudioFrameCount = 4096
    
    // Doppler State Tracking
    private var previousDominantFrequency: Float?
    private var previousFrequencyTimestamp: Double?
    
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var resultsObserver: ThreatResultsObserver?
    
    // 1. Add a cache for the most recent audio buffer
    private var latestBuffer: AVAudioPCMBuffer?
    private var latestTime: AVAudioTime?
    
    func processAudio(buffer: AVAudioPCMBuffer, time: AVAudioTime) async {
        // Continually update the cache
        self.latestBuffer = buffer
        self.latestTime = time
        
        guard let rms = calculateRMS(buffer: buffer) else { return }
        let dbLevel = 20 * log10(max(rms, 1e-10))
        
        if dbLevel > dangerRadiusThresholdDB {
            sustainedAudioFrames += 1
            let currentSustainTime = Double(sustainedAudioFrames * Int(bufferSize)) / sampleRate
            
            if currentSustainTime >= minimumSustainTime {
                streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
            }
        } else {
            sustainedAudioFrames = 0
        }
    }
    func setupAnalyzer(format: AVAudioFormat) throws {
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        
        // 5. Inject 'self' into the observer
        let observer = ThreatResultsObserver(pipeline: self)
        
        self.resultsObserver = observer
        
        try streamAnalyzer?.add(request, withObserver: observer)
    }
    
    /// Calculates the Angle of Arrival (AoA) in degrees using cross-correlation.
    /// Returns an angle between 0.0 and 180.0, or nil if the correlation is too weak.
    func calculateTDOAVector(buffer: AVAudioPCMBuffer) async -> Double? {
        
        // 1. Ensure we have stereo data (Mic 1 and Mic 2)
        guard let channelData = buffer.floatChannelData, buffer.format.channelCount >= 2 else {
            print("Error: TDOA requires at least a 2-channel audio stream.")
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        
        // iPhone constants
        let speedOfSound: Double = 343.0 // meters per second
        let micDistance: Double = 0.15 // roughly 15cm between top and bottom mics
        
        // Max possible sample delay (if sound arrives perfectly in-line with the mics)
        let maxTimeDelay = micDistance / speedOfSound
        let maxSampleDelay = Int(ceil(maxTimeDelay * sampleRate))
        
        let signalA = channelData[0] // e.g., Bottom Mic
        let signalB = channelData[1] // e.g., Top Mic
        
        // 2. Perform Cross-Correlation using vDSP
        // We only need to slide the signals by +/- maxSampleDelay, not the whole buffer
        let correlationLength = (maxSampleDelay * 2) + 1
        var correlationResult = [Float](repeating: 0.0, count: correlationLength)
        
        // vDSP_conv performs the sliding dot product
        // We offset signalB to look backwards and forwards in time relative to signalA
        let signalBPtr = signalB.advanced(by: max(0, frameLength - maxSampleDelay - correlationLength))
        
        vDSP_conv(signalA, 1,
                  signalBPtr, 1,
                  &correlationResult, 1,
                  vDSP_Length(correlationLength),
                  vDSP_Length(frameLength - correlationLength))
        
        // 3. Find the peak of the cross-correlation
        var peakValue: Float = 0.0
        var peakIndex: vDSP_Length = 0
        vDSP_maxvi(&correlationResult, 1, &peakValue, &peakIndex, vDSP_Length(correlationLength))
        
        // Convert the array index back into a sample lag (-maxSampleDelay to +maxSampleDelay)
        let sampleLag = Int(peakIndex) - maxSampleDelay
        
        // 4. Convert sample lag to Time Delay (Delta t)
        let deltaT = Double(sampleLag) / sampleRate
        
        // 5. Calculate Angle of Arrival using the Inverse Cosine (Arccos)
        let ratio = (deltaT * speedOfSound) / micDistance
        
        // Clamp the ratio between -1.0 and 1.0 to prevent NaN crashes due to minor DSP noise
        let clampedRatio = max(-1.0, min(1.0, ratio))
        
        // Angle in radians
        let thetaRadians = acos(clampedRatio)
        
        // Convert to Degrees (0 to 180)
        let thetaDegrees = thetaRadians * (180.0 / .pi)
        
        return thetaDegrees
    }
    
    // Remove the `time: AVAudioTime` parameter here
    func confirmThreatAndTrack(label: String) async {
        
        await PerformanceLogger.shared.start(task: "Spatial_And_Doppler_Tracking")
        
        // Safely unwrap BOTH the buffer and the time from the cache
        guard let buffer = latestBuffer, let time = latestTime else { return }
        
        print("🚨 ML Confirmed Threat: \(label). Analyzing vector & shift...")
        
        // Run TDOA and FFT in parallel
        async let tdoaTask = calculateTDOAVector(buffer: buffer)
        
        // Pass the cached time into the Doppler function
        async let dopplerTask = calculateDopplerShift(buffer: buffer, time: time)
        
        let (angleDegrees, shift) = await (tdoaTask, dopplerTask)
        
        if let angle = angleDegrees {
            print("🧭 Bearing: \(String(format: "%.1f", angle))°")
        }
        
        if let shift = shift {
            let direction = shift.isApproaching ? "APPROACHING ⚠️" : "Receding 📉"
            print("🔊 Doppler: \(direction) (Shift: \(String(format: "%.1f", shift.rate)) Hz/sec)")
        }
        
        await PerformanceLogger.shared.stop(task: "Spatial_And_Doppler_Tracking")
    }
    
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelDataValue = channelData[0]
        var rms: Float = 0.0
        vDSP_rmsqv(channelDataValue, 1, &rms, UInt(buffer.frameLength))
        return rms
    }
}

extension AcousticProcessingPipeline {
    
    /// Analyzes the buffer's frequency spectrum to determine the Doppler shift.
    func calculateDopplerShift(buffer: AVAudioPCMBuffer, time: AVAudioTime) async -> (isApproaching: Bool, rate: Float)? {
        
        guard let channelData = buffer.floatChannelData else { return nil }
        
        // 1. FFT Setup
        let frameCount = buffer.frameLength
        let log2n = vDSP_Length(log2(Float(frameCount)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // 2. Prepare the data (Mono channel 0)
        var signal = [Float](repeating: 0.0, count: Int(frameCount))
        memcpy(&signal, channelData[0], Int(frameCount) * MemoryLayout<Float>.size)
        
        // 3. Apply a Hann Window to smooth the edges and reduce spectral leakage
        var window = [Float](repeating: 0.0, count: Int(frameCount))
        vDSP_hann_window(&window, vDSP_Length(frameCount), Int32(vDSP_HANN_NORM))
        vDSP_vmul(signal, 1, window, 1, &signal, 1, vDSP_Length(frameCount))
        
        let halfSize = Int(frameCount / 2)
        var realp = [Float](repeating: 0.0, count: halfSize)
        var imagp = [Float](repeating: 0.0, count: halfSize)
        var magnitudes = [Float](repeating: 0.0, count: halfSize)
        
        // --- THE FIX: Safe Pointer Scoping ---
        // 4. Safely extract pointers that outlive the DSPSplitComplex initialization
        realp.withUnsafeMutableBufferPointer { realpBuffer in
            imagp.withUnsafeMutableBufferPointer { imagpBuffer in
                
                guard let realPtr = realpBuffer.baseAddress,
                      let imagPtr = imagpBuffer.baseAddress else { return }
                
                var splitComplex = DSPSplitComplex(realp: realPtr, imagp: imagPtr)
                
                // Pack the data
                signal.withUnsafeBytes { ptr in
                    let complexPtr = ptr.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complexPtr.baseAddress!, 2, &splitComplex, 1, vDSP_Length(halfSize))
                }
                
                // 5. Execute the Forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                
                // 6. Calculate Magnitudes
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }
        // --- End of safe pointer scope ---
        
        // 7. Find the Dominant Frequency (The Peak)
        var peakMagnitude: Float = 0.0
        var peakIndex: vDSP_Length = 0
        vDSP_maxvi(&magnitudes, 1, &peakMagnitude, &peakIndex, vDSP_Length(halfSize))
        
        // Convert the bin index to Hertz
        let nyquist = Float(buffer.format.sampleRate / 2.0)
        let binResolution = nyquist / Float(halfSize)
        let dominantFrequency = Float(peakIndex) * binResolution
        
        // THE FIX: Cast Int64 to Double
        let currentTime = Double(time.sampleTime) / buffer.format.sampleRate
        var shiftResult: (isApproaching: Bool, rate: Float)? = nil
        
        // 8. Calculate the Doppler Shift over time
        if let prevFreq = previousDominantFrequency, let prevTime = previousFrequencyTimestamp {
            let timeDelta = Float(currentTime - prevTime)
            
            if timeDelta > 0 {
                let frequencyDelta = dominantFrequency - prevFreq
                let rateOfChange = frequencyDelta / timeDelta
                
                // If pitch is increasing (positive rate), it is approaching.
                let isApproaching = rateOfChange > 5.0
                shiftResult = (isApproaching, rateOfChange)
            }
        }
        
        // Save current state for the next buffer
        self.previousDominantFrequency = dominantFrequency
        self.previousFrequencyTimestamp = currentTime
        
        return shiftResult
    }
}

// MARK: - Core ML Results Observer

/// SoundAnalysis requires an NSObject conforming to SNResultsObserving.
/// We use this class to filter the raw ML outputs and alert the actor of target matches.
// 1. Mark as final and @unchecked Sendable
final class ThreatResultsObserver: NSObject, @unchecked Sendable, SNResultsObserving {
    
    // 2. Hold a weak reference to the actor directly
    private weak var pipeline: AcousticProcessingPipeline?
    
    private let targetThreats: Set<String> = [
        "siren", "ambulance (siren)", "police car (siren)",
        "fire engine, fire truck (siren)", "motorcycle"
    ]
    
    // 3. Explicitly mark the custom initializer as nonisolated
    nonisolated init(pipeline: AcousticProcessingPipeline) {
        self.pipeline = pipeline
        super.init()
    }
    
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        guard let topClassification = classificationResult.classifications.first else { return }
        
        if topClassification.confidence > 0.80 {
            let label = topClassification.identifier.lowercased()
            if targetThreats.contains(where: { label.contains($0) }) {
                
                // 4. Call back to the actor asynchronously
                Task {
                    await pipeline?.confirmThreatAndTrack(label: label)
                }
            }
        }
    }
}
