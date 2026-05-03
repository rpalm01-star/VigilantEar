import SwiftUI

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
            .allowsHitTesting(false)
            .padding(.horizontal, 20)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: consolidatedEvents.count)
    }
    
    private var consolidatedEvents: [SoundEvent] {
        let now = Date()
        
        // 1. THE VIP BOUNCER: Uses global lifespan
        let revealedEvents = events.filter { event in
            guard now.timeIntervalSince(event.timestamp) < AppGlobals.Timing.hudEventLifespan else { return false }
            
            let profile = SoundProfile.classify(event.threatLabel)
            return event.confidence >= profile.revealThreshold
        }
        
        var dictionary: [String: SoundEvent] = [:]
        
        // 2. Collapse logic
        for event in revealedEvents {
            let isMusic = event.threatLabel.lowercased().contains("music")
            let key = isMusic ? "music_king" : event.threatLabel
            
            if let existing = dictionary[key] {
                if event.energy > existing.energy {
                    dictionary[key] = event
                }
            } else {
                dictionary[key] = event
            }
        }
        
        return dictionary.values.sorted(by: { $0.timestamp > $1.timestamp })
    }
}

// MARK: - Individual HUD Item
struct ThreatHUDItemInstance: View {
    var event: SoundEvent
    
    var body: some View {
        let profile = SoundProfile.classify(event.threatLabel)
        
        // NEW: Use unique per-vehicle tint for the inner icon only
        // (background circle and text label stay the canonical profile color)
        let iconColor = event.trackedTarget?.iconTintColor ?? profile.color
        
        let rawLabel = event.threatLabel.replacingOccurrences(of: "_", with: " ").capitalized
        let displayLabel = rawLabel
        
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .stroke(profile.color.opacity(Double(event.energy)), lineWidth: 3)   // keep profile color for ring
                    .frame(width: 54, height: 54)
                
                Image(systemName: profile.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconColor)                    // ← tinted per vehicle
                    .symbolEffect(.bounce, value: event.energy)
                
                Circle()
                    .trim(from: 0.0, to: 0.05)
                    .stroke(profile.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))  // keep profile color for bearing
                    .frame(width: 62, height: 62)
                    .rotationEffect(.degrees(Double(event.bearing) - 90))
            }
            
            Text(displayLabel)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(profile.color)                    // keep canonical color for label
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
    }
}
