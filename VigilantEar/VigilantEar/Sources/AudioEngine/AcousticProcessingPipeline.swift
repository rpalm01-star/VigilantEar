//  AcousticProcessingPipeline.swift
//  VigilantEar

@preconcurrency import AVFoundation
import Accelerate
import SwiftUI
import CoreLocation
import SoundML
import ShazamKit
import Combine

// MARK: - Core Pipeline Actor

/// `AcousticProcessingPipeline` is the central brain of VigilantEar.
/// It operates as an Actor to ensure all state mutations (threat lists, locations, buffer history)
/// are thread-safe without requiring manual locks.
actor AcousticProcessingPipeline {
    
    // MARK: - Streaming & Output
    
    private let bufferSize: AVAudioFrameCount = 4096
    
    nonisolated let eventStream: AsyncStream<SoundEvent>
    private let continuation: AsyncStream<SoundEvent>.Continuation
    
    nonisolated let songStream: AsyncStream<String?>
    private let songContinuation: AsyncStream<String?>.Continuation
    
    // MARK: - Processors & Managers
    
    private let fftProcessor: FFTProcessor
    private let soundMLAnalyzer: Analyzer
    
    struct ActiveThreat {
        var sessionID: UUID
        var dopplerTracker: SirenDopplerTracker
        var lastFrequency: Double
        var lastBearing: Double
        var firstSeen: Date
        var lastSeen: Date
        var category: String
        var label: String
        var hitCount: Int
        var tailMemory: Double
        var hasBeenRevealed: Bool = false
    }
    
    private var activeThreats: [ActiveThreat] = []
    private var bufferHistory: [AVAudioPCMBuffer] = []
    private let maxHistoryFrames = 8
    
    private var sampleRate: Double = 44100.0
    private var lastKnownLocation: CLLocationCoordinate2D?
    private var lastKnownHeading: Double = 0.0
    private var processThisFrameForML: Bool = true
    
    // MARK: - Shazam State
    @Published var currentSongLabel: String?
    private var expireTask: Task<Void, Never>?
    private let shazamCooldown: TimeInterval = 300 // 5 minutes
    private var isAnalyzerSetup = false
    private var isMusicCurrentlyPlaying = false
    private var isShazamRequestInFlight: Bool = false
    private var hasMatchedCurrentSong = false
    private var lastSongUpdate: Date = .distantPast
    private var isAccumulatingForShazam = false
    private var accumulatedFrames: AVAudioFrameCount = 0
    private var shazamSession: SHSession?
    private var shazamDelegate: ShazamResultsObserver?
    private var signatureGenerator = SHSignatureGenerator()
    private var shazamConverter: AVAudioConverter?
    private var shazamMonoBuffer: AVAudioPCMBuffer?
    
    // MARK: - Audio Downsampler State (Moved inside Actor)
    private var audioConverter: AVAudioConverter?
    private var downsampledFormat: AVAudioFormat?
    
    // MARK: - Initialization
    
    init(soundMLAnalyzer: Analyzer) {
        let (stream, cont) = AsyncStream.makeStream(of: SoundEvent.self)
        self.eventStream = stream
        self.continuation = cont
        
        let (sStream, sCont) = AsyncStream.makeStream(of: String?.self)
        self.songStream = sStream
        self.songContinuation = sCont
        
        self.fftProcessor = FFTProcessor(fftSize: Int(self.bufferSize))
        self.soundMLAnalyzer = soundMLAnalyzer
        
        Task {
            await self.setupAnalyzer()
        }
    }
    
    private func setupAnalyzer() async {
        self.soundMLAnalyzer.onUpdate = { [weak self] didMatch, matches in
            guard let self, didMatch, let matches = matches else { return }
            
            // 🚨 OPTIMIZATION: The Math Gatekeeper
            // Filter out garbage guesses and only take the top 2 loudest sounds
            let significantMatches = matches
                .filter { $0.confidence >= 0.10 } // Discard anything under 10% confidence
                .sorted { $0.confidence > $1.confidence }
                .prefix(2) // Only process a maximum of 2 sounds per frame
            
            for match in significantMatches {
                Task {
                    await self.handleMLMatch(label: match.sound.label, confidence: match.confidence)
                }
            }
        }
    }
    
    private func handleMLMatch(label: String, confidence: Double) async {
        let profile = await SoundProfile.classify(label)
        Task.detached(priority: .background) {
            await DependencyContainer.shared.soundLabelEventManager.addOrUpdateDetached(label, confidence: confidence)
        }
        //AppGlobals.doLog(message: "🚨 SoundML Gatekeeper detected: \(label) (\(confidence)) → \(profile.category)", step: "SoundML.handleMLMatch")
        await self.confirmThreatAndTrack(profile: profile, confidence: confidence)
    }
    
    // MARK: - Lifecycle Updates
    
    public func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        self.lastKnownLocation = coordinate
    }
    
    public func updateHeading(_ heading: Double) {
        self.lastKnownHeading = heading
    }
    
    // MARK: - Audio Conversion Logic
    
    private func getDownsampledBuffer(from originalBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let targetSampleRate = 16000.0
        
        if downsampledFormat == nil {
            downsampledFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1, // Mono
                interleaved: false
            )
            
            guard let target = downsampledFormat else { return nil }
            audioConverter = AVAudioConverter(from: originalBuffer.format, to: target)
        }
        
        guard let converter = audioConverter, let target = downsampledFormat else { return nil }
        
        let ratio = targetSampleRate / originalBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(originalBuffer.frameLength) * ratio)
        guard let downsampledBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        
        class ConversionState {
            var hasProvidedData = false
        }
        
        let state = ConversionState()
        
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            // 2. Access the boolean through the wrapper
            if state.hasProvidedData {
                outStatus.pointee = .noDataNow
                return nil
            }
            
            // 3. Update the boolean through the wrapper
            state.hasProvidedData = true
            
            outStatus.pointee = .haveData
            return originalBuffer
        }
        
        var error: NSError?
        converter.convert(to: downsampledBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            AppGlobals.doLog(message: "⚠️ Audio downsample failed: \(error.localizedDescription)", step: "AUDIO_PIPELINE", isError: true)
            return nil
        }
        
        return downsampledBuffer
    }
    
    // MARK: - Core Audio Ingestion Loop
    
    func processAudio(buffer: AVAudioPCMBuffer, time: AVAudioTime) async {
        if !isAnalyzerSetup {
            try? setupShazam(format: buffer.format)
        }
        
        self.sampleRate = buffer.format.sampleRate
        
        // 1. ALWAYS keep the full-res stereo history intact
        bufferHistory.append(buffer)
        if bufferHistory.count > maxHistoryFrames {
            bufferHistory.removeFirst()
        }
        
        // 2. ML Engine: 50% Throttle + 81% Data Reduction
        if processThisFrameForML {
            if let lightBuffer = getDownsampledBuffer(from: buffer) {
                soundMLAnalyzer.process(buffer: lightBuffer, time: time)
            } else {
                soundMLAnalyzer.process(buffer: buffer, time: time)
            }
        }
        processThisFrameForML.toggle()
        
        // 3. 🚨 OPTIMIZATION: The Shazam Hard-Gate
        // We only append buffers if we are actively seeking a match
        if isAccumulatingForShazam {
            processShazamAccumulation(buffer: buffer)
        }
    }
    
    // MARK: - Heavy Lifting
    
    func confirmThreatAndTrack(profile: SoundProfile, confidence: Double) async {
        let now = Date()
        
        let isVehicle = await profile.isVehicle
        let isMusic = await profile.isMusic
        let isEmergency = await profile.isEmergency
        let categoryRawValue = profile.category.rawValue
        let shouldSnapToRoad = profile.shouldSnapToRoad
        let ceiling = profile.ceiling
        let maxRange = profile.maxRange
        let leadInTime = profile.leadInTime
        let tailMemory = profile.tailMemory
        let minimumPeak: Float = isVehicle ? AppGlobals.Physics.minimumVehiclePeak : AppGlobals.Physics.minimumAmbientPeak
        let effectiveLabel = profile.canonicalLabel
        let effectiveConfidence = confidence
        let minimumConfidence = profile.minimumConfidence
        
        let localSampleRate = self.sampleRate
        let exactMicDistance = await HardwareCalibration.micBaseline
        let currentLoc = self.lastKnownLocation
        let currentHead = self.lastKnownHeading
        let songToAttach = self.currentSongLabel
        
        if isMusic {
            self.isMusicCurrentlyPlaying = true
            if !self.isShazamRequestInFlight {
                let timeSinceLastMatch = now.timeIntervalSince(self.lastSongUpdate)
                // 🚀 OPTIMIZATION: Use the 5-minute cooldown, not the 15-second threshold
                if !self.hasMatchedCurrentSong || timeSinceLastMatch > self.shazamCooldown {
                    self.isShazamRequestInFlight = true
                    self.startShazamAccumulation()
                }
            }
        }
        
        if AppGlobals.filteredCategories.contains(categoryRawValue) { return }
        
        if isVehicle && effectiveConfidence < 0.35 {
            let isMusicPresent = activeThreats.contains { $0.label == "music" && now.timeIntervalSince($0.lastSeen) < 5.0 }
            if isMusicPresent { return }
        }
        
        if isEmergency && effectiveConfidence < minimumConfidence { return }
        
        guard let bestBuffer = findPeakBuffer(in: bufferHistory),
              let channelData = bestBuffer.floatChannelData else { return }
        
        let safeCount = min(Int(bestBuffer.frameLength), 4096)
        var maxVal: Float = 0.0
        vDSP_maxmgv(channelData[0], 1, &maxVal, vDSP_Length(safeCount))
        var w_peak = maxVal
        
        if isVehicle { w_peak = max(w_peak, minimumPeak + 0.01) }
        else if isEmergency { w_peak = Float(ceiling) }
        
        guard w_peak > minimumPeak else { return }
        
        let leftChannelCopy = Array(UnsafeBufferPointer(start: channelData[0], count: safeCount))
        let rightChannelCopy = bestBuffer.format.channelCount >= 2 ? Array(UnsafeBufferPointer(start: channelData[1], count: safeCount)) : []
        
        let analysisResult = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return ([(frequency: Double, confidence: Float)](), 0.0) }
            
            var targets = self.fftProcessor.analyzeMultiple(samples: leftChannelCopy, sampleRate: localSampleRate, maxPeaks: 1)
            
            if isVehicle { targets = [(frequency: 100.0, confidence: Float(effectiveConfidence))] }
            else if isEmergency { targets = [(frequency: 0.0, confidence: Float(effectiveConfidence))] }
            else if targets.isEmpty { return ([], 0.0) }
            
            let currentBearing: Double
            if !rightChannelCopy.isEmpty {
                currentBearing = self.fftProcessor.calculateTDOA(
                    left: leftChannelCopy, right: rightChannelCopy,
                    sampleRate: localSampleRate, micDistance: exactMicDistance) ?? 0.0
            } else {
                currentBearing = 0.0
            }
            
            return (targets, currentBearing)
        }.value
        
        let (targets, currentBearing) = analysisResult
        if targets.isEmpty { return }
        
        let safeTailMemory = max(tailMemory, profile.cooldown + 1.0)
        activeThreats.removeAll { now.timeIntervalSince($0.lastSeen) > safeTailMemory }
        
        for target in targets {
            let currentFreq = target.frequency
            var matchIndex: Int? = nil
            
            for (index, threat) in activeThreats.enumerated() {
                if threat.label == effectiveLabel {
                    if now.timeIntervalSince(threat.lastSeen) <= profile.cooldown {
                        matchIndex = index; break
                    }
                    
                    let bearingDiff = abs(threat.lastBearing - currentBearing)
                    let shortestDiff = min(bearingDiff, 360.0 - bearingDiff)
                    let tolerance: Double = isMusic ? 360.0 : (isVehicle ? max(AppGlobals.Physics.vehicleBearingTolerance, 15.0) : AppGlobals.Physics.ambientBearingTolerance)
                    
                    if shortestDiff <= tolerance {
                        matchIndex = index; break
                    }
                }
            }
            
            let threatSessionID: UUID
            let dopplerResult: (isApproaching: Bool, shiftHz: Double)?
            let threatFirstSeen: Date
            var isCurrentlyRevealed = false
            
            if let index = matchIndex {
                activeThreats[index].lastFrequency = currentFreq
                activeThreats[index].lastBearing = (activeThreats[index].lastBearing * 0.7) + (currentBearing * 0.3)
                activeThreats[index].lastSeen = now
                activeThreats[index].hitCount += 1
                dopplerResult = (isVehicle || isMusic) ? nil : activeThreats[index].dopplerTracker.update(with: currentFreq, confidence: target.confidence)
                
                threatSessionID = activeThreats[index].sessionID
                threatFirstSeen = activeThreats[index].firstSeen
                
                if now.timeIntervalSince(threatFirstSeen) >= leadInTime && effectiveConfidence >= minimumConfidence {
                    activeThreats[index].hasBeenRevealed = true
                }
                isCurrentlyRevealed = activeThreats[index].hasBeenRevealed
            } else {
                let newID = UUID()
                var newTracker = SirenDopplerTracker()
                dopplerResult = newTracker.update(with: currentFreq, confidence: target.confidence)
                let instantReveal = (0.0 >= leadInTime && effectiveConfidence >= minimumConfidence)
                
                activeThreats.append(ActiveThreat(
                    sessionID: newID, dopplerTracker: newTracker, lastFrequency: currentFreq,
                    lastBearing: currentBearing, firstSeen: now, lastSeen: now,
                    category: categoryRawValue, label: effectiveLabel, hitCount: 1, tailMemory: safeTailMemory
                ))
                threatSessionID = newID
                threatFirstSeen = now
                isCurrentlyRevealed = instantReveal
            }
            
            Task.detached(priority: .userInitiated) { [weak self, threatSessionID, currentBearing, currentLoc, currentHead, effectiveLabel, effectiveConfidence, songToAttach, isVehicle, isMusic, shouldSnapToRoad, ceiling, maxRange, isCurrentlyRevealed] in
                guard let self = self else { return }
                
                let ambientFloor: Double = isVehicle ? 0.015 : 0.04
                let safePeak = min(max(Double(w_peak), ambientFloor), ceiling)
                let linearRatio = (ceiling - safePeak) / (ceiling - ambientFloor)
                let adjustedMaxRange = isVehicle ? 600.0 : maxRange
                let curvePower = isVehicle ? 2.0 : 2.5
                let estimatedFeet = max(10.0, pow(linearRatio, curvePower) * adjustedMaxRange)
                let normalizedUI_Distance = estimatedFeet / 1000.0
                
                var targetLat: Double? = nil
                var targetLon: Double? = nil
                
                if let origin = currentLoc {
                    let earthRadius = 6378137.0
                    let distanceMeters = estimatedFeet * 0.3048
                    let angularDist = distanceMeters / earthRadius
                    let trueBearing = (currentHead + currentBearing).truncatingRemainder(dividingBy: 360.0)
                    let bearingRad = trueBearing * .pi / 180.0
                    
                    let originLatRad = origin.latitude * .pi / 180.0
                    let originLonRad = origin.longitude * .pi / 180.0
                    
                    let destLatRad = asin(sin(originLatRad) * cos(angularDist) + cos(originLatRad) * sin(angularDist) * cos(bearingRad))
                    let destLonRad = originLonRad + atan2(
                        sin(bearingRad) * sin(angularDist) * cos(originLatRad),
                        cos(angularDist) - sin(originLatRad) * sin(destLatRad)
                    )
                    
                    let rawTargetLat = destLatRad * 180.0 / .pi
                    let rawTargetLon = destLonRad * 180.0 / .pi
                    
                    if shouldSnapToRoad && isCurrentlyRevealed {
                        let rawCoord = CLLocationCoordinate2D(latitude: rawTargetLat, longitude: rawTargetLon)
                        let snappedCoord = await DependencyContainer.shared.roadManager.snapToNearestRoad(rawCoordinate: rawCoord)
                        targetLat = snappedCoord.latitude
                        targetLon = snappedCoord.longitude
                    } else {
                        targetLat = rawTargetLat; targetLon = rawTargetLon
                    }
                }
                
                let attachedSong = isMusic ? songToAttach : nil
                let dopplerRate = dopplerResult?.shiftHz != nil ? Float(dopplerResult!.shiftHz) : nil
                let isApproaching = dopplerResult?.isApproaching ?? false
                
                let newEvent = SoundEvent(
                    sessionID: threatSessionID, timestamp: Date(), threatLabel: effectiveLabel,
                    confidence: effectiveConfidence, bearing: currentBearing, distance: normalizedUI_Distance,
                    energy: Float(safePeak), dopplerRate: dopplerRate, isApproaching: isApproaching,
                    latitude: targetLat, longitude: targetLon, isRevealed: isCurrentlyRevealed, songLabel: attachedSong, profile: profile)
                
                await MainActor.run {
                    if isCurrentlyRevealed && isEmergency {
                        DependencyContainer.shared.notificationManager.sendEmergencyAlert(for: effectiveLabel)
                    }
                }
                _ = self.continuation.yield(newEvent)
            }
        }
    }
    
    // MARK: - Utilities
    
    private func findPeakBuffer(in history: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        var bestBuffer: AVAudioPCMBuffer? = nil
        var highestPeak: Float = -1.0
        
        for buffer in history {
            guard let channelData = buffer.floatChannelData else { continue }
            let safeCount = min(Int(buffer.frameLength), 4096)
            var maxVal: Float = 0.0
            vDSP_maxmgv(channelData[0], 1, &maxVal, vDSP_Length(safeCount))
            
            if maxVal > highestPeak {
                highestPeak = maxVal
                bestBuffer = buffer
            }
        }
        return bestBuffer ?? history.last
    }
    
    // MARK: - Shazam Logic
    
    private func setupShazam(format: AVAudioFormat) throws {
        guard !isAnalyzerSetup else { return }
        isAnalyzerSetup = true
        
        let shazamFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        self.shazamConverter = AVAudioConverter(from: format, to: shazamFormat)
        self.shazamMonoBuffer = AVAudioPCMBuffer(pcmFormat: shazamFormat, frameCapacity: 8192)
        
        self.signatureGenerator = SHSignatureGenerator()
        let shazamObs = ShazamResultsObserver(pipeline: self)
        self.shazamDelegate = shazamObs
        self.shazamSession = SHSession()
        self.shazamSession?.delegate = shazamObs
        
        AppGlobals.doLog(message: "♪ Shazam Initialized Successfully", step: "ML")
    }
    
    func startShazamAccumulation() {
        guard !isAccumulatingForShazam else { return }
        isAccumulatingForShazam = true
        self.signatureGenerator = SHSignatureGenerator()
        self.accumulatedFrames = 0
    }
    
    private func processShazamAccumulation(buffer: AVAudioPCMBuffer) {
        // Redundant checks removed because this is strictly gated by `isAccumulatingForShazam` in `processAudio`
        guard let converter = shazamConverter,
              let monoBuffer = shazamMonoBuffer else { return }
        
        monoBuffer.frameLength = buffer.frameLength
        var hasProvidedBuffer = false
        var error: NSError?
        
        converter.convert(to: monoBuffer, error: &error) { _, outStatus in
            if hasProvidedBuffer {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedBuffer = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        try? signatureGenerator.append(monoBuffer, at: nil)
        accumulatedFrames += monoBuffer.frameLength
        
        if accumulatedFrames >= AVAudioFrameCount(monoBuffer.format.sampleRate * 8) {
            let signature = signatureGenerator.signature()
            if signature.duration > 3.0, let session = shazamSession {
                session.match(signature)
            }
            
            // 🚨 THE FIX: Instantly close the gate.
            // Stop spending CPU cycles hashing audio while we wait for the network.
            self.isAccumulatingForShazam = false
            self.signatureGenerator = SHSignatureGenerator()
            self.accumulatedFrames = 0
        }
    }
    
    // Add this to AcousticProcessingPipeline
    func handleShazamFailure() async {
        // Release the master lock so we can try again later
        self.isShazamRequestInFlight = false
        self.isAccumulatingForShazam = false
        
        // Optional: Log it so you can see network drops in the console
        AppGlobals.doLog(message: "SHAZAM ⚠️ Match failed or timed out. Lock released.", step: "SHAZAM")
    }
    
    func registerShazamResponse(title: String, artist: String) async {
        self.isShazamRequestInFlight = false
        
        lastSongUpdate = Date()
        
        if (artist.isEmpty && title.isEmpty) {
            // Don't clear the currentSongLabel...let it age off naturally in case there was a gap in detection.
            isAccumulatingForShazam = false
            return
        }
        
        expireTask?.cancel()
        
        let songLabelConstruction = "♪ \(title) by \(artist)"
        self.currentSongLabel = songLabelConstruction
        hasMatchedCurrentSong = true
        isAccumulatingForShazam = false
        expireTask = Task {
            // Sleep for 3 minutes (180 seconds)
            try? await Task.sleep(for: .seconds(180))
            if !Task.isCancelled {
                self.currentSongLabel = nil
            }
        }
        
        _ = songContinuation.yield(songLabelConstruction)
    }
}
