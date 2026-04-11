import SwiftUI
import CoreHaptics

struct PulseData: Equatable, Identifiable {
    let id = UUID()
    let bearing: Double
    let distance: Double
    let startTime: TimeInterval
    let energy: Float
    let label: String
}

struct RadarView: View {
    @Environment(MicrophoneManager.self) private var micManager
    
    @State private var engine: CHHapticEngine?
    
    @State private var activePulses: [PulseData] = []
    @State private var lastPulseTimes: [String: Date] = [:]
    
    // --- HUD DATA EXTRACTORS ---
    var topThreats: [SoundEvent] {
        extractTopThreats(from: micManager.events, inTopHemisphere: true)
    }
    
    var bottomThreats: [SoundEvent] {
        extractTopThreats(from: micManager.events, inTopHemisphere: false)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            
            // --- TOP HUD ---
            ThreatHUD(threats: topThreats)
                .frame(height: 60)
            
            // --- THE RADAR ---
            GeometryReader { geometry in
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let radius = min(size.width, size.height) / 2.1
                        
                        // 1. BACKGROUND RINGS
                        for i in 1...4 {
                            let r = radius * CGFloat(i) / 4
                            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                            ctx.stroke(Path { $0.addEllipse(in: rect) }, with: .color(.green.opacity(0.15)), lineWidth: 1)
                        }
                        
                        let nowInterval = timeline.date.timeIntervalSinceReferenceDate
                        
                        // 2. ALWAYS-ON RESTING HEARTBEAT
                        let idleDuration: TimeInterval = 3.0
                        let idleAge = nowInterval.truncatingRemainder(dividingBy: idleDuration)
                        let progress = CGFloat(idleAge / idleDuration)
                        
                        let waveLeadingEdge = (radius * 1.1) * progress
                        let waveThickness = radius * 0.45
                        
                        let startR = max(0, waveLeadingEdge - waveThickness)
                        let endR = max(0.1, waveLeadingEdge)
                        
                        let globalFade = progress > 0.85 ? 1.0 - ((progress - 0.85) / 0.15) : 1.0
                        let idleOpacity = 0.45 * globalFade
                        
                        let gradient = Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .green.opacity(idleOpacity * 0.2), location: 0.5),
                            .init(color: .green.opacity(idleOpacity), location: 0.95),
                            .init(color: .clear, location: 1.0)
                        ])
                        
                        let waveRect = CGRect(
                            x: center.x - waveLeadingEdge,
                            y: center.y - waveLeadingEdge,
                            width: waveLeadingEdge * 2,
                            height: waveLeadingEdge * 2
                        )
                        
                        ctx.fill(
                            Path { $0.addEllipse(in: waveRect) },
                            with: .radialGradient(gradient, center: center, startRadius: startR, endRadius: endR)
                        )
                        
                        // 3. TARGETED SONAR PULSES
                        let pulseDuration: TimeInterval = 1.5
                        
                        for pulse in activePulses {
                            let age = nowInterval - pulse.startTime
                            
                            if age < pulseDuration {
                                let pulseCenter = polarToCartesian(angle: pulse.bearing, radius: radius * CGFloat(pulse.distance), center: center)
                                
                                let currentRadius = 150.0 * CGFloat(age / pulseDuration)
                                let opacity = 1.0 - (age / pulseDuration)
                                
                                let pulseRect = CGRect(
                                    x: pulseCenter.x - currentRadius,
                                    y: pulseCenter.y - currentRadius,
                                    width: currentRadius * 2,
                                    height: currentRadius * 2
                                )
                                
                                ctx.stroke(Path { $0.addEllipse(in: pulseRect) }, with: .color(.green.opacity(opacity)), lineWidth: 2.5)
                            }
                        }
                        
                        // 4. DOTS
                        for event in micManager.events {
                            let relativeAngle = event.bearing
                            let dotPos = polarToCartesian(angle: relativeAngle, radius: radius * CGFloat(event.distance), center: center)
                            
                            let age = timeline.date.timeIntervalSince(event.timestamp)
                            let ageFade = max(0.0, 1.0 - (age / 5.0))
                            let finalOpacity = Double(event.energy) * ageFade
                            
                            let color = event.isApproaching ? Color.red : Color.cyan
                            
                            let coreSize = 26.0 * CGFloat(event.energy)
                            let glowSize = 40.0 * CGFloat(event.energy)
                            
                            let coreRect = CGRect(x: dotPos.x - coreSize/2, y: dotPos.y - coreSize/2, width: coreSize, height: coreSize)
                            let glowRect = CGRect(x: dotPos.x - glowSize/2, y: dotPos.y - glowSize/2, width: glowSize, height: glowSize)
                            
                            ctx.fill(Path { $0.addEllipse(in: glowRect) }, with: .color(color.opacity(finalOpacity * 0.4)))
                            ctx.fill(Path { $0.addEllipse(in: coreRect) }, with: .color(color.opacity(finalOpacity)))
                        }
                    }
                }
                .background(Color.black)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.green.opacity(0.3), lineWidth: 3))
                .contentShape(Circle())
                .onChange(of: micManager.events) { _, events in triggerPulseIfNeeded(events: events) }
                .overlay(alignment: .top) {
                    if micManager.isTestMode {
                        Text("TEST MODE ON")
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .padding(.top, 12)
                    }
                }
                .gesture(TapGesture(count: 2).onEnded { micManager.toggleTestMode() })
                .onAppear { startHapticEngine() }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal)
            
            // --- BOTTOM HUD ---
            ThreatHUD(threats: bottomThreats)
                .frame(height: 60)
            
        }
        .padding(.vertical)
    }
    
    // MARK: - HUD Logic Helpers
    private func extractTopThreats(from events: [SoundEvent], inTopHemisphere: Bool) -> [SoundEvent] {
        let now = Date()
        let genericLabels = ["Acoustic Event", "Monitoring..."]
        
        var validEvents = events.filter {
            !genericLabels.contains($0.threatLabel) &&
            now.timeIntervalSince($0.timestamp) < 2.0
        }
        
        validEvents = validEvents.filter { event in
            let isTop = abs(event.bearing) <= 90
            return inTopHemisphere ? isTop : !isTop
        }
        
        var uniqueThreats: [SoundEvent] = []
        var seenLabels = Set<String>()
        
        for event in validEvents.sorted(by: { $0.timestamp > $1.timestamp }) {
            if !seenLabels.contains(event.threatLabel) {
                uniqueThreats.append(event)
                seenLabels.insert(event.threatLabel)
            }
            if uniqueThreats.count == 3 { break }
        }
        
        return uniqueThreats
    }
    
    private func polarToCartesian(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let rad = (angle - 90) * .pi / 180
        return CGPoint(x: center.x + radius * cos(rad), y: center.y + radius * sin(rad))
    }
    
    // MARK: - Core Logic Helpers
    private func triggerPulseIfNeeded(events: [SoundEvent]) {
        let now = Date()
        let currentTime = CFAbsoluteTimeGetCurrent()
        activePulses.removeAll { currentTime - $0.startTime > 1.5 }
        
        let genericLabels = ["Acoustic Event", "Music", "Monitoring..."]
        let activeThreats = events.filter {
            !genericLabels.contains($0.threatLabel) &&
            $0.energy > 0.05 &&
            now.timeIntervalSince($0.timestamp) < 1.0
        }
        
        var didFireNewPulse = false
        
        for threat in activeThreats {
            let lastTime = lastPulseTimes[threat.threatLabel] ?? .distantPast
            
            if now.timeIntervalSince(lastTime) > 1.5 {
                let newPulse = PulseData(bearing: threat.bearing, distance: threat.distance, startTime: currentTime, energy: threat.energy, label: threat.threatLabel)
                activePulses.append(newPulse)
                lastPulseTimes[threat.threatLabel] = now
                didFireNewPulse = true
            } else {
                if let active = activePulses.last(where: { $0.label == threat.threatLabel }), threat.energy > active.energy + 0.15 {
                    let newPulse = PulseData(bearing: threat.bearing, distance: threat.distance, startTime: currentTime, energy: threat.energy, label: threat.threatLabel)
                    activePulses.append(newPulse)
                    lastPulseTimes[threat.threatLabel] = now
                    didFireNewPulse = true
                }
            }
        }
        
        if didFireNewPulse { triggerDirectionalHaptic() }
    }
    
    private func startHapticEngine() {
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {}
    }
    
    private func triggerDirectionalHaptic() {
        guard let engine else { return }
        let pattern = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
        ], relativeTime: 0)
        
        do {
            let player = try engine.makePlayer(with: CHHapticPattern(events: [pattern], parameters: []))
            try player.start(atTime: 0)
        } catch {}
    }
}

// MARK: - HUD UI Components
struct ThreatHUD: View {
    let threats: [SoundEvent]
    
    var body: some View {
        HStack(spacing: 35) {
            ForEach(threats, id: \.threatLabel) { threat in
                VStack(spacing: 6) {
                    Image(systemName: iconFor(label: threat.threatLabel))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, options: .repeating, isActive: true)
                    
                    Text(threat.threatLabel)
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(.green.opacity(0.8))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: threats.map { $0.threatLabel })
    }
    
    private func iconFor(label: String) -> String {
        switch label.lowercased() {
        case let l where l.contains("bell"): return "bell.fill"
        case let l where l.contains("music"): return "music.quarternote.3"
        case let l where l.contains("knock"): return "hand.tap.fill"
        case let l where l.contains("ambulance"), let l where l.contains("siren"): return "light.beacon.max.fill"
        case let l where l.contains("speech"), let l where l.contains("voice"): return "waveform"
        case let l where l.contains("dog"), let l where l.contains("bark"): return "pawprint.fill"
        case let l where l.contains("cough"): return "lungs.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }
}
