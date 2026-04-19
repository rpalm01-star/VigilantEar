import SwiftUI

// THE FIX 1: Strict categories so the whole app speaks the same language!
enum ThreatCategory {
    case emergency, vehicle, medium, quiet, animal, misc, unknown
}

// MARK: - Classification Engine
struct SoundProfile {
    let icon: String
    let color: Color
    let ceiling: Double
    let maxRange: Double
    let category: ThreatCategory
    
    var isEmergency: Bool { return category == .emergency }
    var isVehicle: Bool { return category == .vehicle }
    
    // 1. THE REGISTRY
    private static let registry: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory)] = [
        
        // --- EMERGENCY ---
        (["ambulance", "siren", "alarm", "emergency", "fire", "detecctor"], "light.beacon.max.fill", .red, 0.80, 1000.0, .emergency),
        (["tornado"], "tornado", .teal, 0.80, 1000.0, .emergency),
        (["glass", "shatter", "crash"], "burst.fill", .pink, 0.80, 1000.0, .emergency),
        
        // --- VEHICLES ---
        (["car", "engine", "traffic"], "car.fill", .blue, 0.15, 300.0, .vehicle),
        (["subway"], "tram.fill.tunnel", .blue, 0.15, 300.0, .vehicle),
        (["train", "rail"], "lightrail.fill", .blue, 0.15, 300.0, .vehicle),
        (["horn"], "horn", .purple, 0.80, 1000.0, .vehicle),
        
        // --- MEDIUM ACTION ---
        (["speech", "voice", "talk", "person"], "waveform", .cyan, 0.55, 150.0, .medium),
        (["bicycle"], "bicycle", .blue, 0.55, 150.0, .medium),
        (["bell", "chime", "clock", "tick", "beep"], "bell.fill", .purple, 0.55, 150.0, .medium),
        (["music", "choir", "song", "sing", "whistl", "didgeridoo", "bassoon", "tuning"], "music.note", .purple, 0.55, 150.0, .medium),
        (["knock", "tap", "hammer", "chopping", "tennis"], "hand.tap.fill", .purple, 0.55, 150.0, .medium),
        (["step", "walk", "foot", "bowling"], "figure.walk", .cyan, 0.55, 150.0, .medium),
        (["water", "rain", "splash"], "drop.fill", .teal, 0.55, 150.0, .medium),
        (["wind", "breeze"], "wind", .teal, 0.55, 150.0, .medium),
        (["baby", "cry"], "stroller.fill", .pink, 0.55, 150.0, .medium),
        
        // --- QUIET / BIOLOGICAL ---
        (["snap", "zipper", "keyboard", "typing"], "hand.point.up.left.fill", .purple, 0.35, 30.0, .quiet),
        (["breathing", "cough"], "lungs.fill", .cyan, 0.35, 30.0, .quiet),
        (["sneeze", "nose"], "nose.fill", .cyan, 0.35, 30.0, .quiet),
        (["snoring", "snore", "sleep"], "zzz", .cyan, 0.35, 30.0, .quiet),
        (["burp", "hiccup", "swallow"], "mouth.fill", .cyan, 0.35, 30.0, .quiet),
        (["laugh", "chuckle"], "face.smiling.fill", .cyan, 0.35, 30.0, .quiet),
        
        // --- ANIMALS ---
        (["bird", "chirp", "owl hoot"], "bird.fill", .green, 0.35, 30.0, .animal),
        (["cat"], "cat", .green, 0.35, 30.0, .animal),
        (["dog"], "dog", .green, 0.35, 30.0, .animal),
        (["bark", "animal", "pig"], "pawprint.fill", .green, 0.35, 30.0, .animal),
        
        // --- MISC ---
        (["fan"], "fan", .mint, 0.35, 30.0, .misc),
        (["crumpl", "crush", "trash"], "trash.fill", .mint, 0.35, 30.0, .misc),
        (["toilet", "flush"], "toilet.fill", .mint, 0.35, 30.0, .misc),
        (["door"], "door.right.hand.closed", .mint, 0.35, 30.0, .misc),
    ]
    
    // 2. THE SEARCH ENGINE
    static func classify(_ label: String) -> SoundProfile {
        let lowerLabel = label.lowercased()
        
        for entry in registry {
            if entry.keywords.contains(where: { lowerLabel.contains($0) }) {
                return SoundProfile(
                    icon: entry.icon,
                    color: entry.color,
                    ceiling: entry.ceiling,
                    maxRange: entry.maxRange,
                    category: entry.category // NEW
                )
            }
        }
        
        // THE FALLBACK
        return SoundProfile(icon: "waveform", color: .gray, ceiling: 0.55, maxRange: 150.0, category: .unknown)
    }
}

// MARK: - The HUD View
struct ThreatHUD: View {
    var events: [SoundEvent]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(consolidatedEvents, id: \.threatLabel) { event in
                    ThreatHUDItemInstance(event: event)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: consolidatedEvents.count)
    }
    
    private var consolidatedEvents: [SoundEvent] {
        let now = Date()
        let recent = events.filter { now.timeIntervalSince($0.timestamp) < 3.0 }
        
        var dictionary: [String: SoundEvent] = [:]
        for event in recent {
            if let existing = dictionary[event.threatLabel] {
                if event.energy > existing.energy {
                    dictionary[event.threatLabel] = event
                }
            } else {
                dictionary[event.threatLabel] = event
            }
        }
        return dictionary.values.sorted(by: { $0.timestamp > $1.timestamp })
    }
}

// MARK: - The Individual Instrument UI
struct ThreatHUDItemInstance: View {
    var event: SoundEvent
    
    var body: some View {
        // Fetch the unified profile!
        let profile = SoundProfile.classify(event.threatLabel)
        let displayLabel = event.threatLabel.replacingOccurrences(of: "_", with: " ").capitalized
        
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .stroke(profile.color.opacity(Double(event.energy)), lineWidth: 3)
                    .frame(width: 54, height: 54)
                
                Image(systemName: profile.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(profile.color)
                    .symbolEffect(.bounce, value: event.energy)
                
                Circle()
                    .trim(from: 0.0, to: 0.05)
                    .stroke(profile.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 62, height: 62)
                    .rotationEffect(.degrees(Double(event.bearing) - 90))
            }
            
            Text(displayLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(1))
                .lineLimit(1)
                .frame(width: 60)
        }
    }
}
