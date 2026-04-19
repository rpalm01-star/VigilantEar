//
//  SoundProfile.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/15/26.
//

import SwiftUI

// MARK: - Classification Engine
// The unified source of truth for both UI rendering and Acoustic Physics
struct SoundProfile {
    let icon: String
    let color: Color
    let ceiling: Double
    let maxRange: Double
    
    // 1. THE REGISTRY (Your internal "JSON" lookup table)
    // Organized by physics class, then by specific icon
    private static let registry: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double)] = [
        
        // --- EMERGENCY (Loud: 0.80 / 1000ft) ---
        (["ambulance", "siren", "alarm", "emergency", "fire", "detecctor"], "light.beacon.max.fill", .red, 0.80, 1000.0),
        (["tornado"], "tornado", .teal, 0.80, 1000.0),
        (["glass", "shatter", "crash"], "burst.fill", .pink, 0.80, 1000.0),
        
        // --- VEHICLES (Loud: 0.80 / 1000ft) ---
        (["car", "engine", "traffic"], "car.fill", .blue, 0.80, 1000.0),
        (["subway"], "tram.fill.tunnel", .blue, 0.80, 1000.0),
        (["train", "rail"], "lightrail.fill", .blue, 0.80, 1000.0),
        (["horn"], "horn", .purple, 0.80, 1000.0),
        
        // --- MEDIUM ACTION (Medium: 0.55 / 150ft) ---
        (["speech", "voice", "talk", "person"], "waveform", .cyan, 0.55, 150.0),
        (["bicycle"], "bicycle", .blue, 0.55, 150.0),
        (["bell", "chime", "clock", "tick", "beep"], "bell.fill", .purple, 0.55, 150.0),
        (["music", "choir", "song", "sing", "whistl", "didgeridoo", "bassoon", "tuning"], "music.note", .purple, 0.55, 150.0),
        (["knock", "tap", "hammer", "chopping", "tennis"], "hand.tap.fill", .purple, 0.55, 150.0),
        (["step", "walk", "foot", "bowling"], "figure.walk", .cyan, 0.55, 150.0),
        (["water", "rain", "splash"], "drop.fill", .teal, 0.55, 150.0),
        (["wind", "breeze"], "wind", .teal, 0.55, 150.0),
        (["baby", "cry"], "stroller.fill", .pink, 0.55, 150.0),
        
        // --- QUIET / BIOLOGICAL (Quiet: 0.35 / 30ft) ---
        (["snap", "zipper", "keyboard", "typing"], "hand.point.up.left.fill", .purple, 0.35, 30.0),
        (["breathing", "cough"], "lungs.fill", .cyan, 0.35, 30.0),
        (["sneeze", "nose"], "nose.fill", .cyan, 0.35, 30.0),
        (["snoring", "snore", "sleep"], "zzz", .cyan, 0.35, 30.0),
        (["burp", "hiccup", "swallow"], "mouth.fill", .cyan, 0.35, 30.0),
        (["laugh", "chuckle"], "face.smiling.fill", .cyan, 0.35, 30.0),
        
        // --- ANIMALS (Quiet: 0.35 / 30ft) ---
        (["bird", "chirp", "owl hoot"], "bird.fill", .green, 0.35, 30.0),
        (["cat"], "cat", .green, 0.35, 30.0),
        (["dog"], "dog", .green, 0.35, 30.0),
        (["bark", "animal", "pig"], "pawprint.fill", .green, 0.35, 30.0),
        
        // --- MISC ---
        (["fan"], "fan", .mint, 0.35, 30.0),
        (["crumpl", "crush", "trash"], "trash.fill", .mint, 0.35, 30.0),
        (["toilet", "flush"], "toilet.fill", .mint, 0.35, 30.0),
        (["door"], "door.right.hand.closed", .mint, 0.35, 30.0),

    ]
    
    // 2. THE SEARCH ENGINE
    static func classify(_ label: String) -> SoundProfile {
        let lowerLabel = label.lowercased()
        
        // Scan the registry for a keyword match
        for entry in registry {
            if entry.keywords.contains(where: { lowerLabel.contains($0) }) {
                return SoundProfile(
                    icon: entry.icon,
                    color: entry.color,
                    ceiling: entry.ceiling,
                    maxRange: entry.maxRange
                )
            }
        }
        
        // THE FALLBACK: If we've never seen it before, assume it's medium
        return SoundProfile(icon: "waveform", color: .gray, ceiling: 0.55, maxRange: 150.0)
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
