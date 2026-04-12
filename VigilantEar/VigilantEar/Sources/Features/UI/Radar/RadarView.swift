import SwiftUI
import CoreHaptics


// A high-speed memory lock to prevent 60 FPS haptic queueing
class HapticCooldownManager {
    var lastFired: [String: Date] = [:]
}

struct PulseData: Equatable, Identifiable {
    let id = UUID()
    let bearing: Double
    let distance: Double
    let startTime: TimeInterval
    let energy: Float
    let label: String
}

// --- RESTORED: Stable Dot View (No Blink) ---
struct RadarDotView: View {
    let event: SoundEvent
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        let centerX = width / 2
        let centerY = height / 2
        
        // Coordinates
        let radians = CGFloat(event.bearing) * .pi / 180.0
        let xOffset = CGFloat(event.distance) * (width / 2) * sin(radians)
        let yOffset = -CGFloat(event.distance) * (height / 2) * cos(radians)
        
        // Threat Analysis
        let label = event.threatLabel.lowercased()
        let isEmergency = label.contains("siren") || label.contains("ambulance") || label.contains("firetruck")
        
        // Make emergency vehicles visually distinct
        let dotColor = isEmergency ? Color.red : Color.cyan
        
        Circle()
            .fill(dotColor)
            .frame(width: 16, height: 16)
            .shadow(color: dotColor, radius: CGFloat(event.energy) * 15)
            .position(x: centerX + xOffset, y: centerY + yOffset)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: event.distance)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: event.bearing)
    }
}

// --- UPDATED: Device Radar View with Flashing Inner Zone ---
struct DeviceRadarView: View {
    var events: [SoundEvent]
    
    // Background heartbeat for the warning zone
    @State private var isBlinking = false
    
    var body: some View {
        // Determine if ANY emergency vehicle is inside the 0.25 threshold
        let isBreaching = events.contains { event in
            let label = event.threatLabel.lowercased()
            let isEmergency = label.contains("siren") || label.contains("ambulance") || label.contains("firetruck")
            return isEmergency && abs(event.distance) <= 0.25
        }
        
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let centerX = width / 2
            let centerY = height / 2
            
            ZStack {
                // 1. Draw the "Phone Outline" grid
                ForEach(1...4, id: \.self) { ring in
                    let scale = CGFloat(ring) / 4.0
                    
                    let shadingOpacity = 0.20 - (Double(ring) * 0.03)
                    let borderOpacity = 0.35 - (Double(ring) * 0.05)
                    
                    // --- THE RED ALERT LOGIC ---
                    let isInnerRing = (ring == 1)
                    let isWarningActive = isInnerRing && isBreaching
                    
                    let ringColor = isWarningActive ? Color.red : Color.green
                    // If it's a warning, pulse the opacity between high (0.35) and low (0.05)
                    let finalShading = isWarningActive ? (isBlinking ? 0.35 : 0.05) : shadingOpacity
                    
                    RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                        .fill(ringColor.opacity(finalShading))
                        .background(
                            RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                            // Thicker border when alarming
                                .stroke(ringColor.opacity(borderOpacity), lineWidth: isWarningActive ? 2 : 1)
                        )
                        .frame(width: width * scale, height: height * scale)
                }
                
                // 2. Draw subtle crosshairs
                Path { path in
                    path.move(to: CGPoint(x: centerX, y: 0))
                    path.addLine(to: CGPoint(x: centerX, y: height))
                    path.move(to: CGPoint(x: 0, y: centerY))
                    path.addLine(to: CGPoint(x: width, y: centerY))
                }
                .stroke(Color.green.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // 3. Plot the acoustic events
                ForEach(events, id: \.timestamp) { event in
                    RadarDotView(event: event, width: width, height: height)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .onAppear {
            // Start the infinite heartbeat the moment the radar loads
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                isBlinking = true
            }
        }
    }
}

struct RadarView: View {
    @Environment(MicrophoneManager.self) private var micManager
    
    @State private var engine: CHHapticEngine?
    @State private var hapticGatekeeper = HapticCooldownManager()
    
    // --- HUD DATA EXTRACTORS ---
    // Notice these now return [String] instead of [SoundEvent]
    var topThreats: [String] {
        extractTopThreatLabels(from: micManager.events, inTopHemisphere: true)
    }
    
    var bottomThreats: [String] {
        extractTopThreatLabels(from: micManager.events, inTopHemisphere: false)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            
            // --- TOP HUD ---
            ThreatHUD(threatLabels: topThreats)
                .frame(height: 60)
            
            // --- THE DEVICE RADAR ---
            DeviceRadarView(events: micManager.events)
                .background(Color.black)
                .onChange(of: micManager.events) { _, events in
                    checkInnerRingCrossing(events: events)
                }
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
            
            // --- BOTTOM HUD ---
            ThreatHUD(threatLabels: bottomThreats)
                .frame(height: 60)
            
        }
        .padding(.vertical)
        .onAppear { startHapticEngine() }
    }
    
    // --- HUD DATA EXTRACTORS ---
    
    // MARK: - HUD Logic Helpers
    private func extractTopThreatLabels(from events: [SoundEvent], inTopHemisphere: Bool) -> [String] {
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
        
        var uniqueLabels: [String] = []
        var seenLabels = Set<String>()
        
        // We still sort by timestamp to find the latest active threats...
        for event in validEvents.sorted(by: { $0.timestamp > $1.timestamp }) {
            if !seenLabels.contains(event.threatLabel) {
                uniqueLabels.append(event.threatLabel)
                seenLabels.insert(event.threatLabel)
            }
            if uniqueLabels.count == 3 { break }
        }
        
        // ...but we return them sorted alphabetically so they lock their physical positions on screen!
        return uniqueLabels.sorted()
    }
    
    private func checkInnerRingCrossing(events: [SoundEvent]) {
        let now = Date()
        let innerRingThreshold: Double = 0.25
        
        for event in events {
            let label = event.threatLabel.lowercased()
            
            if label.contains("siren") || label.contains("ambulance") || label.contains("firetruck") {
                if abs(event.distance) <= innerRingThreshold {
                    
                    // Look up the cooldown for THIS specific unique threat label
                    let lastTime = hapticGatekeeper.lastFired[event.threatLabel] ?? .distantPast
                    
                    // If this specific siren hasn't fired in 10 seconds...
                    if now.timeIntervalSince(lastTime) > 10.0 {
                        triggerSirenProximityHaptic()
                        
                        // Instantly lock the memory gate for this siren
                        hapticGatekeeper.lastFired[event.threatLabel] = now
                    }
                }
            }
        }
    }
    
    // MARK: - Haptics
    private func startHapticEngine() {
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {}
    }
    
    private func triggerSirenProximityHaptic() {
        guard let engine else { return }
        
        let pulse1 = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        ], relativeTime: 0)
        
        let pulse2 = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        ], relativeTime: 0.15)
        
        do {
            // Stop any rogue lingering patterns just in case
            engine.stop(completionHandler: nil)
            try engine.start()
            
            let player = try engine.makePlayer(with: CHHapticPattern(events: [pulse1, pulse2], parameters: []))
            try player.start(atTime: 0)
        } catch {}
    }
}
// MARK: - HUD UI Components
// [Stable sort logic maps down to strings and alphabetically sorts labels logic]
struct ThreatHUD: View {
    let threatLabels: [String] // Input logic stable [String]
    
    var body: some View {
        HStack(spacing: 35) {
            ForEach(threatLabels, id: \.self) { label in
                VStack(spacing: 6) {
                    Image(systemName: iconFor(label: label))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, options: .repeating, isActive: true)
                    
                    // Hidden ID handling logic preserved, splitting at `_`.
                    Text(formatLabel(label))
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(.green.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: threatLabels)
    }
    
    private func formatLabel(_ label: String) -> String {
        let parts = label.components(separatedBy: "_")
        if parts.count == 1 { return label }
        return "\(parts[0])\n\(parts[1])"
    }
    
    private func iconFor(label: String) -> String {
        switch label.lowercased() {
        case let l where l.contains("bell"): return "bell.fill"
        case let l where l.contains("music") || l.contains("song"): return "music.quarternote.3"
        case let l where l.contains("knock") || l.contains("tap"): return "hand.tap.fill"
        case let l where l.contains("ambulance") || l.contains("siren") || l.contains("alarm"): return "light.beacon.max.fill"
        case let l where l.contains("speech") || l.contains("voice") || l.contains("talk"): return "waveform"
        case let l where l.contains("dog") || l.contains("bark") || l.contains("animal"): return "pawprint.fill"
        case let l where l.contains("cough"): return "lungs.fill"
        case let l where l.contains("sneeze"): return "nose.fill"
        case let l where l.contains("snore") || l.contains("sleep"): return "zzz"
        case let l where l.contains("burp") || l.contains("hiccup") || l.contains("swallow"): return "mouth.fill"
        case let l where l.contains("laugh") || l.contains("chuckle"): return "face.smiling.fill"
        case let l where l.contains("clock") || l.contains("tick") || l.contains("chime"): return "clock.fill"
        case let l where l.contains("glass") || l.contains("shatter") || l.contains("crash"): return "burst.fill"
        case let l where l.contains("step") || l.contains("walk") || l.contains("foot"): return "figure.walk"
        case let l where l.contains("water") || l.contains("rain") || l.contains("splash"): return "drop.fill"
        case let l where l.contains("wind") || l.contains("breeze"): return "wind"
        case let l where l.contains("car") || l.contains("engine") || l.contains("traffic"): return "car.fill"
        case let l where l.contains("bird") || l.contains("chirp"): return "bird.fill"
        case let l where l.contains("baby") || l.contains("cry"): return "stroller.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }
}
