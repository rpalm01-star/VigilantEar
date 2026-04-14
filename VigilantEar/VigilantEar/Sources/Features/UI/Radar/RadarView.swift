import SwiftUI
import CoreHaptics
import Combine

// MARK: - Supporting Logic

class HapticCooldownManager {
    var lastFired: [String: Date] = [:]
}

struct RadarDotView: View {
    let event: SoundEvent
    let width: CGFloat
    let height: CGFloat
    
    @State private var now = Date()
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        let isSimulated = event.threatLabel.contains("Fire")
        let multiplier: CGFloat = isSimulated ? 1.0 : 4.0
        let displayAngle = CGFloat(event.bearing) * multiplier

        let radians = displayAngle * .pi / 180.0

        // X moves Left/Right
        let xOffset = CGFloat(event.distance) * (width / 2) * sin(radians)
        
        // Y moves Top/Bottom.
        // IMPORTANT: To match your "Top" earpiece and "Bottom" port:
        // We use a negative cos to ensure -Bearing (Bottom) = +Y (Down)
        let yOffset = -CGFloat(event.distance) * (height / 2) * cos(radians)
        
        Circle()
            .fill(event.dotColor.opacity(max(0, 1.0 - (now.timeIntervalSince(event.timestamp) / 1.5))))
            .frame(width: 22, height: 22)
            .offset(x: xOffset, y: yOffset)
            .onReceive(timer) { now = $0 }
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.7), value: event.bearing)
    }
}

// MARK: - Main Radar Components

struct DeviceRadarView: View {
    var events: [SoundEvent]
    
    @State private var isBlinking = false
    @State private var rippleScale: CGFloat = 0.25
    @State private var rippleOpacity: Double = 0.0
    
    var body: some View {
        let isBreaching = events.contains { $0.isEmergency && abs($0.distance) <= 0.25 }
        
        GeometryReader { geo in
            let maxWidth = geo.size.width
            let maxHeight = geo.size.height
            let targetRatio: CGFloat = 0.65
            
            let isWider = (maxWidth / maxHeight) > targetRatio
            let radarHeight: CGFloat = isWider ? maxHeight : (maxWidth / targetRatio)
            let radarWidth: CGFloat  = isWider ? (maxHeight * targetRatio) : maxWidth
            
            let centerX = maxWidth / 2
            let centerY = maxHeight / 2
            
            ZStack {
                // Radar Rings
                ForEach(1...4, id: \.self) { ring in
                    let scale = CGFloat(ring) / 4.0
                    let shadingOpacity = 0.20 - (Double(ring) * 0.03)
                    let borderOpacity = 0.35 - (Double(ring) * 0.05)
                    
                    let isInnerRing = (ring == 1)
                    let isWarningActive = isInnerRing && isBreaching
                    let ringColor = isWarningActive ? Color.red : Color.green
                    let finalShading = isWarningActive ? (isBlinking ? 0.35 : 0.05) : shadingOpacity
                    
                    ZStack(alignment: .top) {
                        // The Ring Shape
                        RoundedRectangle(cornerRadius: isInnerRing ? 16 : 30 * scale, style: .continuous)
                            .fill(ringColor.opacity(finalShading))
                            .background(
                                RoundedRectangle(cornerRadius: isInnerRing ? 16 : 30 * scale, style: .continuous)
                                    .stroke(ringColor.opacity(borderOpacity), lineWidth: isWarningActive ? 2 : 1)
                            )
                        
                        // PHYSICAL DISTANCE LABELS (30ft scale)
                        let distanceInFeet = Int(scale * 30)
                        Text("\(distanceInFeet) ft")
                            .font(.system(size: 10, design: .monospaced).bold())
                            .foregroundStyle(.green.opacity(0.4))
                            .padding(.top, 4)
                        
                        if isInnerRing {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(ringColor.opacity(finalShading))
                                
                                // Use a conditional ZStack to keep the "phone" size consistent
                                ZStack {
                                    if events.isEmpty {
                                        Image(systemName: "iphone")
                                            .resizable()
                                            .scaledToFit()
                                            .padding(8) // Keeps it from touching the edges
                                    } else {
                                        // When active, we use the "radiowaves" icon but
                                        // we force it to ignore the extra width of the waves
                                        // so the phone body stays large.
                                        Image(systemName: "iphone.radiowaves.left.and.right")
                                            .resizable()
                                            .scaledToFit()
                                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
                                        // This padding keeps the waves inside the rectangle
                                            .padding(4)
                                    }
                                }
                                .fontWeight(.light)
                                .foregroundStyle(ringColor.opacity(isWarningActive ? 0.9 : 0.45))
                                
                                // DISTANCE LABEL
                                let distanceInFeet = Int(scale * 30)
                                Text("\(distanceInFeet) ft")
                                    .font(.system(size: 9, design: .monospaced).bold())
                                    .foregroundStyle(.green.opacity(0.6))
                                    .offset(y: -(radarHeight * scale / 2) + 10)
                            }
                            .frame(width: radarWidth * scale, height: radarHeight * scale)
                        }
                    }
                    .frame(width: radarWidth * scale, height: radarHeight * scale)
                }
                
                // Crosshairs
                Path { path in
                    path.move(to: CGPoint(x: centerX, y: centerY - (radarHeight / 2)))
                    path.addLine(to: CGPoint(x: centerX, y: centerY + (radarHeight / 2)))
                    path.move(to: CGPoint(x: centerX - (radarWidth / 2), y: centerY))
                    path.addLine(to: CGPoint(x: centerX + (radarWidth / 2), y: centerY))
                }
                .stroke(Color.green.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // Plot the acoustic events
                ForEach(events) { event in
                    RadarDotView(event: event, width: radarWidth, height: radarHeight)
                }
            }
            .position(x: centerX, y: centerY)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                isBlinking = true
            }
        }
    }
}

struct RadarView: View {
    @Environment(AcousticCoordinator.self) private var coordinator
    @State private var engine: CHHapticEngine?
    @State private var hapticGatekeeper = HapticCooldownManager()
    
    var topThreats: [String] {
        extractThreatLabels(from: coordinator.activeEvents, inTop: true)
    }
    
    var bottomThreats: [String] {
        extractThreatLabels(from: coordinator.activeEvents, inTop: false)
    }
    
    var body: some View {
        VStack(spacing: -10) { // Negative spacing pulls them together
            
            // --- TOP HUD ---
            ThreatHUD(threatLabels: topThreats)
                .frame(height: 50)
                .zIndex(1) // Ensure it stays on top of the radar background
            
            // --- THE DEVICE RADAR ---
            DeviceRadarView(events: coordinator.activeEvents)
                .background(Color.black)
                .onChange(of: coordinator.activeEvents) { _, events in
                    checkInnerRingCrossing(events: events)
                }
            
            // --- BOTTOM HUD ---
            ThreatHUD(threatLabels: bottomThreats)
                .frame(height: 50)
                .zIndex(1)
            // This pulls the bottom HUD UP to touch the radar grid
                .padding(.top, -15)
        }
        .padding(.bottom, 10) // Small padding to keep it off the very edge of the screen
        .onAppear { startHapticEngine() }
    }
    
    private func extractThreatLabels(from events: [SoundEvent], inTop: Bool) -> [String] {
        let now = Date()
        let validEvents = events.filter { now.timeIntervalSince($0.timestamp) < 2.0 }
        
        // HEMISPHERE LOGIC:
        // We divide the HUD based on the bearing.
        // Snaps at the earpiece (Top) usually have bearings near -8 to 0 in your logs.
        // Snaps at the charging port (Bottom) show larger absolute values or flipped polarity.
        let filtered = validEvents.filter { event in
            return inTop ? (event.bearing <= 0) : (event.bearing > 0)
        }
        
        var uniqueLabels: [String] = []
        var seen = Set<String>()
        
        for event in filtered.sorted(by: { $0.timestamp > $1.timestamp }) {
            if !seen.contains(event.threatLabel) {
                uniqueLabels.append(event.threatLabel)
                seen.insert(event.threatLabel)
            }
            if uniqueLabels.count == 3 { break }
        }
        return uniqueLabels.sorted()
    }
    
    private func checkInnerRingCrossing(events: [SoundEvent]) {
        let now = Date()
        for event in events where event.isEmergency && event.distance <= 0.25 {
            let lastTime = hapticGatekeeper.lastFired[event.threatLabel] ?? .distantPast
            if now.timeIntervalSince(lastTime) > 8.0 {
                triggerSirenProximityHaptic()
                hapticGatekeeper.lastFired[event.threatLabel] = now
            }
        }
    }
    
    private func startHapticEngine() {
        do { engine = try CHHapticEngine(); try engine?.start() } catch {}
    }
    
    private func triggerSirenProximityHaptic() {
        guard let engine else { return }
        let p1 = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        ], relativeTime: 0)
        let p2 = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        ], relativeTime: 0.12)
        do {
            try engine.start()
            let player = try engine.makePlayer(with: CHHapticPattern(events: [p1, p2], parameters: []))
            try player.start(atTime: 0)
        } catch {}
    }
}

struct ThreatHUD: View {
    let threatLabels: [String]
    var body: some View {
        HStack(spacing: 20) { // Horizontal gap between different threats
            ForEach(threatLabels, id: \.self) { label in
                VStack(spacing: 0) { // ZERO vertical spacing between icon and text
                    Image(systemName: iconFor(label: label))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.green)
                    
                    Text(label.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.8))
                        .frame(height: 12) // Constrain the text height
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
    
    private func iconFor(label: String) -> String {
        switch label.lowercased() {
        case let l where l.contains("keyboard") || l.contains("typing"): return "keyboard.fill"
        case let l where l.contains("bicycle"): return "bicycle"
        case let l where l.contains("subway"): return "tram.fill.tunnel"
        case let l where l.contains("train") || l.contains("rail"): return "lightrail.fill"
        case let l where l.contains("bell"): return "bell.fill"
        case let l where l.contains("tuning"): return "tuningfork"
        case let l where l.contains("hammer"): return "hammer"
        case let l where l.contains("whistl") || l.contains("didgeridoo") || l.contains("bassoon"): return "music.note"
        case let l where l.contains("music") || l.contains("choir") || l.contains("song") || l.contains("sing"): return "music.quarternote.3"
        case let l where l.contains("knock") || l.contains("tap"): return "hand.tap.fill"
        case let l where l.contains("ambulance") || l.contains("siren") || l.contains("alarm") || l.contains("emergency"): return "light.beacon.max.fill"
        case let l where l.contains("speech") || l.contains("voice") || l.contains("talk"): return "waveform"
        case let l where l.contains("bark") || l.contains("animal"): return "pawprint.fill"
        case let l where l.contains("tornado"): return "tornado"
        case let l where l.contains("person"): return "figure.wave"
        case let l where l.contains("breathing") || l.contains("cough"): return "lungs.fill"
        case let l where l.contains("sneeze") || l.contains("snoring") || l.starts(with: "nose"): return "nose.fill"
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
        case let l where l.contains("bowling"): return "figure.bowling"
        case let l where l.contains("cat"): return "cat"
        case let l where l.contains("dog"): return "dog"
        case let l where l.contains("fan"): return "fan"
        case let l where l.contains("horn"): return "horn"
        default: return "exclamationmark.triangle.fill"
        }
    }
}
