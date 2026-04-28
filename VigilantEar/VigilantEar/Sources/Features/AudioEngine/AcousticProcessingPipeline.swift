@preconcurrency import AVFoundation
import Accelerate
import SoundAnalysis
import SwiftUI
import CoreLocation
import ShazamKit

actor AcousticProcessingPipeline {
    
    private let bufferSize: AVAudioFrameCount = 4096
    
    nonisolated let eventStream: AsyncStream<SoundEvent>
    private let continuation: AsyncStream<SoundEvent>.Continuation
    
    nonisolated let songStream: AsyncStream<String?>
    private let songContinuation: AsyncStream<String?>.Continuation
    
    private let fftProcessor: FFTProcessor
    
    // --- THE INJECTED ROAD MANAGER ---
    private let roadManager: RoadManager
    
    private var isAnalyzerSetup = false
    
    struct ActiveThreat {
        var sessionID: UUID
        var dopplerTracker: SirenDopplerTracker
        var lastFrequency: Double
        var lastBearing: Double
        var firstSeen: Date
        var lastSeen: Date
        var category: String
        var label: String       // 🏷️ NEW: Anchor the object to its name!
        var hitCount: Int
        var tailMemory: Double
    }
    
    private var activeThreats: [ActiveThreat] = []
    
    private var dopplerFrequencyBuffer: [Double] = []
    private let maxDopplerBufferSize = 40
    private var dopplerBaselineCenter: Double?
    
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var resultsObserver: ThreatResultsObserver?
    
    private var shazamSession: SHSession?
    private var shazamDelegate: ShazamResultsObserver?
    private var signatureGenerator = SHSignatureGenerator()
    private var accumulatedFrames: AVAudioFrameCount = 0
    private var sampleRate: Double = 44100.0
    
    private var isMusicCurrentlyPlaying = false
    private var lastMusicDetectedTime: Date = .distantPast
    private var lastShazamMatchTime: Date = .distantPast
    private var hasMatchedCurrentSong = false
    private var currentSongLabel: String? = nil
    private var lastSongUpdate: Date = .distantPast
    private var isAccumulatingForShazam = false
    
    private var latestBuffer: AVAudioPCMBuffer?
    private var latestTime: AVAudioTime?
    
    private var lastKnownLocation: CLLocationCoordinate2D? = nil
    private var lastKnownHeading: Double = 0.0
    
    init(roadManager: RoadManager) {
        let (stream, cont) = AsyncStream.makeStream(of: SoundEvent.self)
        self.eventStream = stream
        self.continuation = cont
        
        let (sStream, sCont) = AsyncStream.makeStream(of: String?.self)
        self.songStream = sStream
        self.songContinuation = sCont
        
        self.fftProcessor = FFTProcessor(fftSize: Int(self.bufferSize))
        self.roadManager = roadManager
    }
    
    public func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        self.lastKnownLocation = coordinate
    }
    
    public func updateHeading(_ heading: Double) {
        self.lastKnownHeading = heading
    }
    
    // MARK: - Shazam (Clean Production Version)
    
    func startShazamAccumulation() {
        guard !isAccumulatingForShazam else { return }
        
        isMusicCurrentlyPlaying = true
        lastMusicDetectedTime = Date()
        isAccumulatingForShazam = true
        
        if hasMatchedCurrentSong && Date().timeIntervalSince(lastSongUpdate) < 180 {
            return
        }
        
        self.signatureGenerator = SHSignatureGenerator()
        self.accumulatedFrames = 0
    }
    
    func processAudio(buffer: AVAudioPCMBuffer, time: AVAudioTime) async {
        self.latestBuffer = buffer
        self.latestTime = time
        
        streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        
        if isMusicCurrentlyPlaying && Date().timeIntervalSince(lastMusicDetectedTime) > 25.0 {
            isMusicCurrentlyPlaying = false
            isAccumulatingForShazam = false
            hasMatchedCurrentSong = false
            currentSongLabel = nil
            _ = songContinuation.yield(nil)
            return
        }
        
        guard isAccumulatingForShazam else { return }
        
        let shazamFormat = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1)!
        let converter = AVAudioConverter(from: buffer.format, to: shazamFormat)
        let monoBuffer = AVAudioPCMBuffer(pcmFormat: shazamFormat, frameCapacity: buffer.frameLength)!
        
        var error: NSError?
        converter?.convert(to: monoBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        try? signatureGenerator.append(monoBuffer, at: time)
        accumulatedFrames += monoBuffer.frameLength
        
        if accumulatedFrames >= AVAudioFrameCount(shazamFormat.sampleRate * 8) {
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
    
    func confirmThreatAndTrack(label: String, confidence: Double) async {
        let now = Date()
        
        let profile = await MainActor.run { SoundProfile.classify(label) }
        
        // Capture everything we need locally
        let isVehicle = await profile.isVehicle
        let isMusic = await profile.isMusic
        let categoryRawValue = profile.category.rawValue
        let shouldSnapToRoad = profile.shouldSnapToRoad
        let hapticCount = profile.hapticCount
        let ceiling = profile.ceiling
        let maxRange = profile.maxRange
        let leadInTime = profile.leadInTime   // ⏳ Capture Physics
        let tailMemory = profile.tailMemory   // 👻 Capture Physics
        
        let minimumPeak: Float = isVehicle ? AppGlobals.Physics.minimumVehiclePeak : AppGlobals.Physics.minimumAmbientPeak
        
        // Let everything through here! The UI handles the reveal mask, we just need it to exist
        // guard confidence >= profile.minimumConfidence else { return } // <-- REMOVED (Handled by UI / Observer)
        
        let effectiveLabel = profile.canonicalLabel
        let effectiveConfidence = confidence
        
        if AppGlobals.filteredCategories.contains(categoryRawValue) {
            return
        }
        
        guard let buffer = latestBuffer, let channelData = buffer.floatChannelData else { return }
        let safeCount = min(Int(buffer.frameLength), 4096)
        let peak = Array(UnsafeBufferPointer(start: channelData[0], count: safeCount)).map(abs).max() ?? 0.0
        
        guard peak > minimumPeak else { return }
        
        var targets = self.fftProcessor.analyzeMultiple(samples: Array(UnsafeBufferPointer(start: channelData[0], count: safeCount)), sampleRate: self.sampleRate, maxPeaks: 1)
        
        if isVehicle {
            targets = [(frequency: 100.0, confidence: Float(effectiveConfidence))]
        } else if targets.isEmpty {
            return
        }
        
        let localSampleRate = self.sampleRate
        let exactMicDistance = await HardwareCalibration.micBaseline
        
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
        
        // 🛡️ DYNAMIC TAIL PROTECTION
        // Ensure the pipeline memory is mathematically guaranteed to be longer than the Observer's cooldown!
        let safeTailMemory = max(tailMemory, profile.cooldown + 1.0)
        activeThreats.removeAll { now.timeIntervalSince($0.lastSeen) > safeTailMemory }
        
        for target in targets {
            let currentFreq = target.frequency
            var matchIndex: Int? = nil
            
            // 🏷️ FIX 1: MATCH BY LABEL
            // This stops echoes from spawning dozens of ghost dots.
            // If we hear the same label, we assume it's the same object and just update its position.
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
                
                // Smooth the bearing so the dot doesn't violently teleport around the map on echoes
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
                    sessionID: newID,
                    dopplerTracker: newTracker,
                    lastFrequency: currentFreq,
                    lastBearing: currentBearing,
                    firstSeen: now,
                    lastSeen: now,
                    category: categoryRawValue,
                    label: effectiveLabel, // 🏷️ Save the label anchor
                    hitCount: 1,
                    tailMemory: safeTailMemory
                ))
                threatSessionID = newID
                threatFirstSeen = now
            }
            
            // ==========================================
            // 🚨 GHOST TRACKING GATE (LEAD-IN TIME)
            // ==========================================
            let timeAlive = now.timeIntervalSince(threatFirstSeen)
            if timeAlive < leadInTime {
                AppGlobals.doLog(message: "👻 GHOST TRACKING: [\(effectiveLabel)] is building history. (Alive: \(String(format: "%.2f", timeAlive))s / Need: \(leadInTime)s)", step: "GHOST_TRACKING")
                continue
            }
            
            let currentLoc = self.lastKnownLocation
            let currentHead = self.lastKnownHeading
            let songToAttach = self.currentSongLabel
            let minConf = profile.minimumConfidence // Capture for the Haptic gate
            
            Task.detached(priority: .userInitiated) { [weak self, threatSessionID, currentBearing, currentLoc, currentHead, effectiveLabel, effectiveConfidence, songToAttach, isVehicle, isMusic, shouldSnapToRoad, hapticCount, ceiling, maxRange, minConf] in
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
                    // ... (Your exact same GPS Math remains unchanged here) ...
                    let earthRadius = 6378137.0
                    let distanceMeters = estimatedFeet * 0.3048
                    let angularDist = distanceMeters / earthRadius
                    let trueBearing = (currentHead + currentBearing).truncatingRemainder(dividingBy: 360.0)
                    let bearingRad = trueBearing * .pi / 180.0
                    let originLatRad = origin.latitude * .pi / 180.0
                    let originLonRad = origin.longitude * .pi / 180.0
                    let destLatRad = asin(sin(originLatRad) * cos(angularDist) + cos(originLatRad) * sin(angularDist) * cos(bearingRad))
                    let destLonRad = originLonRad + atan2(sin(bearingRad) * sin(angularDist) * cos(originLatRad), cos(originLatRad) * sin(destLatRad))
                    
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
                
                let newEvent = SoundEvent(
                    sessionID: threatSessionID,
                    timestamp: Date(),
                    threatLabel: effectiveLabel,
                    realThreatLabel: label,
                    confidence: effectiveConfidence,
                    bearing: currentBearing,
                    distance: normalizedUI_Distance,
                    energy: Float(safePeak),
                    dopplerRate: dopplerResult?.shiftHz != nil ? Float(dopplerResult!.shiftHz) : nil,
                    isApproaching: dopplerResult?.isApproaching ?? false,
                    latitude: targetLat,
                    longitude: targetLon,
                    songLabel: attachedSong
                )
                
                let latStr = targetLat != nil ? String(format: "%.5f", targetLat!) : "N/A"
                let lonStr = targetLon != nil ? String(format: "%.5f", targetLon!) : "N/A"
                let confStr = String(format: "%.3f", effectiveConfidence)
                
                // ✅ FIX 2: Check if the UI is actually going to reveal this sound
                let isRevealed = effectiveConfidence >= minConf
                
                let msg = "Tracked [\(effectiveLabel)] - Dist: \(Int(estimatedFeet))ft, Brg: \(Int(currentBearing))°, LAT: \(latStr), LON: \(lonStr), Conf: \(confStr), Revealed: \(isRevealed)"
                AppGlobals.doLog(message: msg, step: "2_TARGET_TRACKED")
                
                await MainActor.run {
                    if isRevealed {
                        // 1. Fire the physical vibration
                        if hapticCount > 0 {
                            HapticManager.shared.trigger(count: hapticCount, sessionID: threatSessionID)
                        }
                        
                        // 2. 🚨 INJECT NOTIFICATIONS HERE 🚨
                        // If it's a critical emergency, punch a Time Sensitive alert to the lock screen
                        if profile.isEmergency {
                            NotificationManager.shared.sendEmergencyAlert(for: effectiveLabel)
                        }
                    }
                }
                _ = self.continuation.yield(newEvent)
            }
        }
    }
    
    func setupAnalyzer(format: AVAudioFormat) throws {
        guard !isAnalyzerSetup else {
            AppGlobals.doLog(message: "Analyzer already setup. Ignoring redundant call.", step: "ACOUSTIC_PIPLINE_SETUP")
            return
        }
        isAnalyzerSetup = true
        
        self.sampleRate = format.sampleRate
        streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 1000)
        request.overlapFactor = 0.9
        
        let observer = ThreatResultsObserver(pipeline: self)
        self.resultsObserver = observer
        try streamAnalyzer?.add(request, withObserver: observer)
        
        self.signatureGenerator = SHSignatureGenerator()
        
        let shazamObs = ShazamResultsObserver(pipeline: self)
        self.shazamDelegate = shazamObs
        self.shazamSession = SHSession()
        self.shazamSession?.delegate = shazamObs
    }
}
