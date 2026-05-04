@preconcurrency import AVFoundation
import Accelerate
import SoundAnalysis
import SwiftUI
import CoreLocation
import ShazamKit

/// Core actor responsible for real-time audio processing, ML classification,
/// multi-target tracking, TDOA bearing calculation, and event generation.
actor AcousticProcessingPipeline {
    
    private let bufferSize: AVAudioFrameCount = 4096
    
    nonisolated let eventStream: AsyncStream<SoundEvent>
    private let continuation: AsyncStream<SoundEvent>.Continuation
    
    nonisolated let songStream: AsyncStream<String?>
    private let songContinuation: AsyncStream<String?>.Continuation
    
    private let fftProcessor: FFTProcessor
    private let roadManager: RoadManager
    private let soundEventManager: SoundLabelEventManager
    
    private var isAnalyzerSetup = false
    
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
    }
    
    private var activeThreats: [ActiveThreat] = []
    
    private var latestBuffer: AVAudioPCMBuffer?
    private var sampleRate: Double = 44100.0
    private var lastKnownLocation: CLLocationCoordinate2D?
    private var lastKnownHeading: Double = 0.0
    private var currentSongLabel: String?
    
    // Shazam / Music state
    private var isMusicCurrentlyPlaying = false
    private var lastMusicDetectedTime: Date = .distantPast
    private var lastShazamMatchTime: Date = .distantPast
    private var hasMatchedCurrentSong = false
    private var lastSongUpdate: Date = .distantPast
    private var isAccumulatingForShazam = false
    private var accumulatedFrames: AVAudioFrameCount = 0
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var resultsObserver: ThreatResultsObserver?
    private var shazamSession: SHSession?
    private var shazamDelegate: ShazamResultsObserver?
    private var signatureGenerator = SHSignatureGenerator()
    
    private var shazamConverter: AVAudioConverter?
    private var shazamMonoBuffer: AVAudioPCMBuffer?
    
    init(roadManager: RoadManager, soundEventManager: SoundLabelEventManager) {
        let (stream, cont) = AsyncStream.makeStream(of: SoundEvent.self)
        self.eventStream = stream
        self.continuation = cont
        
        let (sStream, sCont) = AsyncStream.makeStream(of: String?.self)
        self.songStream = sStream
        self.songContinuation = sCont
        
        self.fftProcessor = FFTProcessor(fftSize: Int(self.bufferSize))
        self.roadManager = roadManager
        self.soundEventManager = soundEventManager
    }
    
    public func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        self.lastKnownLocation = coordinate
    }
    
    public func updateHeading(_ heading: Double) {
        self.lastKnownHeading = heading
    }
    
    func startShazamAccumulation() {
        guard !isAccumulatingForShazam else { return }
        
        // Just reset the buckets and open the gate
        isAccumulatingForShazam = true
        self.signatureGenerator = SHSignatureGenerator()
        self.accumulatedFrames = 0
    }
    
    func processAudio(buffer: AVAudioPCMBuffer, time: AVAudioTime) async {
        // 1. Ensure setup is called only ONCE.
        if !isAnalyzerSetup {
            try? setupAnalyzer(format: buffer.format)
        }
        
        self.latestBuffer = buffer
        self.sampleRate = buffer.format.sampleRate
        
        // 2. 🚨 THE CRITICAL ML CALL: Feed the model continuously!
        streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        
        // 3. Shazam Timeout Logic
        if isMusicCurrentlyPlaying && Date().timeIntervalSince(lastMusicDetectedTime) > 25.0 {
            isMusicCurrentlyPlaying = false
            isAccumulatingForShazam = false
            hasMatchedCurrentSong = false
            currentSongLabel = nil
            _ = songContinuation.yield(nil)
            return
        }
        
        // 4. Pre-allocated Shazam Processing
        guard isAccumulatingForShazam,
                let converter = shazamConverter,
                let monoBuffer = shazamMonoBuffer else { return }
        
        // --- Inside processAudio() ---
        monoBuffer.frameLength = buffer.frameLength
        
        var hasProvidedBuffer = false
        var error: NSError?
        
        converter.convert(to: monoBuffer, error: &error) { _, outStatus in
            // Only feed the buffer once per conversion pass!
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
            self.signatureGenerator = SHSignatureGenerator()
            self.accumulatedFrames = 0
        }
    }
    
    func registerSongMatch(title: String, artist: String) async {
        let customLabel = "🎵 \(title) by \(artist)"
        currentSongLabel = customLabel
        lastSongUpdate = Date()
        hasMatchedCurrentSong = true
        isAccumulatingForShazam = false
        
        AppGlobals.doLog(message: "Identified: \(customLabel)", step: "SHAZAM")
        _ = songContinuation.yield(customLabel)
    }
    
    nonisolated func sendRawLabelToHUD(_ rawLabel: String, confidence: Double) {
        if (confidence > AppGlobals.NeuralTicker.minimumConfidence) {
            Task.detached { [weak self] in
                self?.soundEventManager.addOrUpdateDetached(rawLabel, confidence: confidence)
            }
        }
    }
    
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
        
        // 🚨 NEW LOGIC: The Music Heartbeat & Cooldown
        if isMusic {
            // Keep the heartbeat alive so the HUD doesn't clear the song
            self.lastMusicDetectedTime = now
            self.isMusicCurrentlyPlaying = true
            
            // Only fire up Shazam if we haven't identified a song in the last 3 minutes
            if !self.hasMatchedCurrentSong || now.timeIntervalSince(self.lastSongUpdate) > 180 {
                self.startShazamAccumulation()
            }
        }
        
        if AppGlobals.filteredCategories.contains(categoryRawValue) { return }
        
        guard let buffer = latestBuffer, let channelData = buffer.floatChannelData else { return }
        let safeCount = min(Int(buffer.frameLength), 4096)
        
        // Zero-allocation hardware peak detection
        var maxVal: Float = 0.0
        vDSP_maxmgv(channelData[0], 1, &maxVal, vDSP_Length(safeCount))
        let peak = maxVal
        
        guard peak > minimumPeak else { return }
        
        let localSampleRate = self.sampleRate
        let exactMicDistance = await HardwareCalibration.micBaseline
        let currentLoc = self.lastKnownLocation
        let currentHead = self.lastKnownHeading
        let songToAttach = self.currentSongLabel
        let minConf = profile.minimumConfidence
        
        let analysisResult = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return ([(frequency: Double, confidence: Float)](), 0.0) }
            
            var targets = self.fftProcessor.analyzeMultiple(
                samples: Array(UnsafeBufferPointer(start: channelData[0], count: safeCount)),
                sampleRate: localSampleRate,
                maxPeaks: 1
            )
            
            if isVehicle {
                targets = [(frequency: 100.0, confidence: Float(effectiveConfidence))]
            } else if targets.isEmpty {
                return ([], 0.0)
            }
            
            let currentBearing: Double
            if buffer.format.channelCount >= 2 {
                currentBearing = self.fftProcessor.calculateTDOA(
                    left: Array(UnsafeBufferPointer(start: channelData[0], count: safeCount)),
                    right: Array(UnsafeBufferPointer(start: channelData[1], count: safeCount)),
                    sampleRate: localSampleRate,
                    micDistance: exactMicDistance
                ) ?? 0.0
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
                    matchIndex = index
                    break
                }
            }
            
            let threatSessionID: UUID
            let dopplerResult: (isApproaching: Bool, shiftHz: Double)?
            let threatFirstSeen: Date
            
            if let index = matchIndex {
                activeThreats[index].lastFrequency = currentFreq
                let oldBearing = activeThreats[index].lastBearing
                activeThreats[index].lastBearing = (oldBearing * 0.7) + (currentBearing * 0.3)
                activeThreats[index].lastSeen = now
                activeThreats[index].hitCount += 1
                dopplerResult = (isVehicle || isMusic) ? nil : activeThreats[index].dopplerTracker.update(with: currentFreq, confidence: target.confidence)
                threatSessionID = activeThreats[index].sessionID
                threatFirstSeen = activeThreats[index].firstSeen
            } else {
                let newID = UUID()
                var newTracker = SirenDopplerTracker()
                dopplerResult = newTracker.update(with: currentFreq, confidence: target.confidence)
                
                activeThreats.append(ActiveThreat(
                    sessionID: newID, dopplerTracker: newTracker, lastFrequency: currentFreq,
                    lastBearing: currentBearing, firstSeen: now, lastSeen: now,
                    category: categoryRawValue, label: effectiveLabel, hitCount: 1, tailMemory: safeTailMemory
                ))
                threatSessionID = newID
                threatFirstSeen = now
            }
            
            let timeAlive = now.timeIntervalSince(threatFirstSeen)
            let hasMetLeadIn = timeAlive >= leadInTime
            
            Task.detached(priority: .userInitiated) { [weak self, threatSessionID, currentBearing, currentLoc, currentHead, effectiveLabel, effectiveConfidence, songToAttach, isVehicle, isMusic, shouldSnapToRoad, ceiling, maxRange, minConf, hasMetLeadIn] in
                guard let self = self else { return }
                
                let ambientFloor: Double = isVehicle ? 0.015 : 0.04
                let safePeak = min(max(Double(peak), ambientFloor), ceiling)
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
                    
                    if shouldSnapToRoad {
                        let rawCoord = CLLocationCoordinate2D(latitude: rawTargetLat, longitude: rawTargetLon)
                        let snappedCoord = await self.roadManager.snapToNearestRoad(rawCoordinate: rawCoord)
                        targetLat = snappedCoord.latitude
                        targetLon = snappedCoord.longitude
                    } else {
                        targetLat = rawTargetLat
                        targetLon = rawTargetLon
                    }
                }
                
                let attachedSong = (isMusic) ? songToAttach : nil
                let dopplerRate = dopplerResult?.shiftHz != nil ? Float(dopplerResult!.shiftHz) : nil
                let isApproaching = dopplerResult?.isApproaching ?? false
                let isRevealed = (hasMetLeadIn && effectiveConfidence >= minConf) || effectiveConfidence >= 0.42
                
                let newEvent = SoundEvent(
                    sessionID: threatSessionID, timestamp: Date(), threatLabel: effectiveLabel,
                    confidence: effectiveConfidence, bearing: currentBearing, distance: normalizedUI_Distance,
                    energy: Float(safePeak), dopplerRate: dopplerRate, isApproaching: isApproaching,
                    latitude: targetLat, longitude: targetLon, isRevealed: isRevealed, songLabel: attachedSong
                )
                
                await MainActor.run {
                    if isRevealed && isEmergency {
                        NotificationManager.shared.sendEmergencyAlert(for: effectiveLabel)
                    }
                }
                _ = self.continuation.yield(newEvent)
            }
        }
    }
    
    func setupAnalyzer(format: AVAudioFormat) throws {
        guard !isAnalyzerSetup else { return }
        // 🚨 CRITICAL: Set to true immediately so we don't get trapped in an infinite re-setup loop
        isAnalyzerSetup = true
        
        self.sampleRate = format.sampleRate
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 1000)
        request.overlapFactor = 0.9
        
        let observer = ThreatResultsObserver(pipeline: self)
        self.resultsObserver = observer
        try streamAnalyzer?.add(request, withObserver: observer)
        
        let shazamFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!
        self.shazamConverter = AVAudioConverter(from: format, to: shazamFormat)
        self.shazamMonoBuffer = AVAudioPCMBuffer(pcmFormat: shazamFormat, frameCapacity: 8192)
        
        self.signatureGenerator = SHSignatureGenerator()
        let shazamObs = ShazamResultsObserver(pipeline: self)
        self.shazamDelegate = shazamObs
        self.shazamSession = SHSession()
        self.shazamSession?.delegate = shazamObs
        
        AppGlobals.doLog(message: "ML Analyzer & Shazam Initialized Successfully", step: "ML")
    }
}
