//
//  SoundProfile.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/15/26.
//


import SwiftUI

// MARK: - Classification Engine
// Maps Apple's raw ML strings to beautiful UI elements
struct SoundProfile {
    let icon: String
    let color: Color
    
    static func classify(_ label: String) -> SoundProfile {
        return evaluateLabel(label: label.lowercased())
    }
    
    private static func evaluateLabel(label: String) -> SoundProfile {
        return SoundProfile(icon: getIconLabel(l: label), color: getIconColor(l: label))
    }
    
    private static func getIconLabel(l: String) -> String {
        switch l {
        case let l where l.contains("ambulance") || l.contains("siren")
            || l.contains("alarm") || l.contains("emergency") || l.contains("fire"): return "light.beacon.max.fill"
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
        default: return "waveform"
        }
    }
    
    private static func getIconColor(l: String) -> Color {
        switch l {
        case let l where l.contains("ambulance") || l.contains("siren")
            || l.contains("alarm") || l.contains("emergency") || l.contains("fire"): return .red
        case let l where l.contains("keyboard") || l.contains("typing"): return .purple
        case let l where l.contains("bicycle"): return .blue
        case let l where l.contains("subway"): return .blue
        case let l where l.contains("train") || l.contains("rail"): return .blue
        case let l where l.contains("bell"): return .purple
        case let l where l.contains("tuning"): return .purple
        case let l where l.contains("hammer"): return .blue
        case let l where l.contains("whistl") || l.contains("didgeridoo") || l.contains("bassoon"): return .purple
        case let l where l.contains("music") || l.contains("choir") || l.contains("song") || l.contains("sing"): return .purple
        case let l where l.contains("knock") || l.contains("tap"): return .purple
        case let l where l.contains("speech") || l.contains("voice") || l.contains("talk"): return .cyan
        case let l where l.contains("bark") || l.contains("animal"): return .green
        case let l where l.contains("tornado"): return .teal
        case let l where l.contains("person"): return .cyan
        case let l where l.contains("breathing") || l.contains("cough"): return .cyan
        case let l where l.contains("sneeze") || l.contains("snoring") || l.starts(with: "nose"): return .cyan
        case let l where l.contains("snore") || l.contains("sleep"): return .cyan
        case let l where l.contains("burp") || l.contains("hiccup") || l.contains("swallow"): return .cyan
        case let l where l.contains("laugh") || l.contains("chuckle"): return .cyan
        case let l where l.contains("clock") || l.contains("tick") || l.contains("chime"): return .purple
        case let l where l.contains("glass") || l.contains("shatter") || l.contains("crash"): return .pink
        case let l where l.contains("step") || l.contains("walk") || l.contains("foot"): return .cyan
        case let l where l.contains("water") || l.contains("rain") || l.contains("splash"): return .teal
        case let l where l.contains("wind") || l.contains("breeze"): return .teal
        case let l where l.contains("car") || l.contains("engine") || l.contains("traffic"): return .blue
        case let l where l.contains("bird") || l.contains("chirp"): return .green
        case let l where l.contains("baby") || l.contains("cry"): return .pink
        case let l where l.contains("bowling"): return .cyan
        case let l where l.contains("cat"): return .green
        case let l where l.contains("dog"): return .green
        case let l where l.contains("fan"): return .gray
        case let l where l.contains("horn"): return .purple
        default: return .gray
        }
    }
    
}

// MARK: - The HUD View
struct ThreatHUD: View {
    // We now take full SoundEvents so we have the telemetry math
    var events: [SoundEvent]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(consolidatedEvents, id: \.threatLabel) { event in
                    AcousticInstrument(event: event)
                    // Smoothly animate icons popping in and out
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
        }
        // Force the animation to trigger when the array changes
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: consolidatedEvents.count)
    }
    
    // Helper to group spammy events.
    // If 10 'speech' events fire in 1 second, we only show 1 icon, but we use the loudest one.
    private var consolidatedEvents: [SoundEvent] {
        let now = Date()
        // Only show sounds from the last 3 seconds
        let recent = events.filter { now.timeIntervalSince($0.timestamp) < 3.0 }
        
        var dictionary: [String: SoundEvent] = [:]
        for event in recent {
            if let existing = dictionary[event.threatLabel] {
                // Keep the one with the highest energy
                if event.energy > existing.energy {
                    dictionary[event.threatLabel] = event
                }
            } else {
                dictionary[event.threatLabel] = event
            }
        }
        
        // Sort by timestamp so the newest sounds are on the left
        return dictionary.values.sorted(by: { $0.timestamp > $1.timestamp })
    }
}

// MARK: - The Individual Instrument UI
struct AcousticInstrument: View {
    var event: SoundEvent
    
    var body: some View {
        let profile = SoundProfile.classify(event.threatLabel)
        let displayLabel = event.threatLabel.replacingOccurrences(of: "_", with: " ").capitalized
        
        VStack(spacing: 6) {
            ZStack {
                // Background Glass
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 50, height: 50)
                
                // Energy Pulse Ring (Opacity based on acoustic energy)
                Circle()
                    .stroke(profile.color.opacity(Double(event.energy)), lineWidth: 3)
                    .frame(width: 54, height: 54)
                
                // The SF Symbol Icon
                Image(systemName: profile.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(profile.color)
                    .symbolEffect(.bounce, value: event.energy) // Bounces when energy changes
                
                // Directional Pointer (Points to the sound!)
                Circle()
                    .trim(from: 0.0, to: 0.05)
                    .stroke(profile.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 62, height: 62)
                // The compass bearing relative to the phone's front
                    .rotationEffect(.degrees(Double(event.bearing) - 90))
            }
            
            // Clean Text Label
            Text(displayLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(1))
                .lineLimit(1)
                .frame(width: 60)
        }
    }
}

