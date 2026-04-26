import SwiftUI

enum ThreatCategory: String, Sendable {
    case emergency, vehicle, medium, quiet, animal, misc, unknown, ignored
}

// MARK: - Classification Engine
struct SoundProfile {
    let icon: String
    let color: Color
    let ceiling: Double
    let maxRange: Double
    let category: ThreatCategory
    let canonicalLabel: String
    let shouldSnapToRoad: Bool
    let hapticCount: Int
    let cooldown: Double          // ← NEW: Recommended debounce time in seconds
    
    // Computed Properties for Logic Gates
    var isEmergency: Bool { return category == .emergency }
    var isVehicle: Bool { return category == .vehicle }
    
    // --- THE THREAD-SAFE CONCURRENT CACHE ---
    private static var lookupTable: [String: SoundProfile] = [:]
    private static let queue = DispatchQueue(label: "com.VigilantEar.profileCache", attributes: .concurrent)
    
    // 1. THE RAW REGISTRY
    // Tuple: (Keywords, Icon, Color, Ceiling, MaxRange, Category, Snaps, Haptics, Cooldown)
    private static let rawRegistry: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double)] = [
        
        // --- 🚨 EMERGENCY / SIRENS (High Priority) ---
        (["siren", "ambulance", "police", "firetruck", "civil_defense", "foghorn", "emergency_vehicle", "simulated_fire_truck"], "light.beacon.max.fill", .red, 0.80, 1000.0, .emergency, true, 3, 1.1),
        
        // --- ⚠️ THREATS / DANGER (High Priority) ---
        (["gunshot", "artillery", "fireworks", "firecracker", "explosion", "boom", "eruption"], "shriker.fill", .red, 0.90, 1000.0, .emergency, false, 2, 1.2),
        
        // --- 👣 PERSONAL SAFETY / APPROACH (High Priority for Safety) ---
        (["footsteps", "walking", "running", "shuffling", "knock", "door_slam", "door_sliding"], "figure.walk.arrival", .red, 0.45, 60.0, .emergency, false, 2, 1.1),
        
        // --- 🔔 CRITICAL ALERTS ---
        (["smoke_detector", "alarm", "telephone_bell", "ringtone", "door_bell", "reverse_beeps"], "exclamationmark.triangle.fill", .red, 0.60, 100.0, .emergency, false, 2, 1.2),
        
        // --- 🚗 VEHICLES (Important but standard) ---
        (["air_horn", "train_horn"], "horn.fill", .purple, 0.80, 1000.0, .emergency, true, 1, 1.2),
        (["car", "truck", "bus", "motorcycle", "traffic", "vehicle", "engine", "engine_accelerating"], "car.fill", .blue, 0.30, 500.0, .vehicle, true, 0, 1.2),
        (["subway", "metro", "train", "railroad", "rail_transport"], "tram.fill.tunnel", .blue, 0.15, 600.0, .ignored, false, 0, 2.2),
        
        // --- 🛠️ WORK / TOOLS ---
        (["hammer", "saw", "drill", "power_tool", "trimmer", "chopping_wood"], "hammer.fill", .orange, 0.60, 100.0, .medium, false, 0, 1.4),
        
        // --- 🎵 THE MUSIC FUNNEL (Informational) ---
        (["music", "horn", "singing", "choir", "yodeling", "rapping", "humming", "whistling", "instrument", "guitar", "piano", "organ", "keyboard_musical", "synthesizer", "drum", "percussion", "orchestra", "brass", "trumpet", "trombone", "violin", "fiddle", "cello", "flute", "saxophone", "clarinet", "oboe", "bassoon", "harp", "harmonica", "accordion", "bagpipes", "didgeridoo", "theremin"], "music.quarternote.3", .purple, 0.55, 150.0, .medium, false, 0, 2.2),
        
        // --- 🗣️ HUMAN VOICE & INTERACTION ---
        (["speech", "shout", "yell", "cry", "scream", "whisper", "laughter", "giggling", "chuckle", "babble", "chatter", "crowd"], "person.wave.2.fill", .cyan, 0.55, 120.0, .medium, false, 0, 1.4),
        (["clapping", "applause", "cheering", "finger_snapping"], "hands.clap.fill", .cyan, 0.50, 80.0, .medium, false, 0, 1.5),
        
        // --- 🐶 ANIMALS ---
        (["dog_growl", "dog_bark", "coyote_howl"], "dog.fill", .brown, 0.40, 150.0, .animal, false, 0, 1.9),
        (["cat", "meow", "purr"], "cat.fill", .brown, 0.35, 40.0, .animal, false, 0, 1.9),
        (["bird", "chirp", "tweet","crow", "pigeon", "duck", "goose", "turkey", "rooster"], "bird.fill", .brown, 0.35, 60.0, .animal, false, 0, 1.8),
        (["horse", "cow", "pig", "sheep", "lion", "elk", "whale", "frog", "snake", "insect", "cricket", "bee"], "pawprint.fill", .brown, 0.40, 100.0, .animal, false, 0, 1.9),
        
        // --- 💧 NATURE & ELEMENTS ---
        (["wind", "thunder", "storm", "rain", "water", "stream", "waterfall", "ocean", "waves", "fire_crackle"], "leaf.arrow.triangle.circlepath", .teal, 0.30, 300.0, .medium, false, 0, 1.5),
        
        // --- 🏠 DOMESTIC / INTERIOR ---
        (["dishes", "cutlery", "frying", "microwave", "blender", "sink", "bathtub", "toilet", "dishwasher", "vacuum", "hair_dryer"], "house.fill", .mint, 0.40, 40.0, .misc, false, 0, 1.6),
        (["typing", "keyboard", "typewriter", "writing", "camera", "printer", "clock", "tick"], "keyboard", .mint, 0.35, 40.0, .misc, false, 0, 1.6),
        (["drawer", "sliding_door", "squeak", "zipper", "keys", "coin"], "door.left.hand.closed", .mint, 0.35, 30.0, .misc, false, 0, 1.6),
        (["glass_clink", "glass_breaking", "shatter"], "tear", .orange, 0.70, 100.0, .misc, false, 1, 1.4),
        
        // --- 💤 BIOLOGICAL / IGNORED ---
        (["breathing", "snoring", "cough", "sneeze", "gasp", "chewing", "biting", "gargling", "burp", "hiccup", "slurp"], "lungs.fill", .gray, 0.20, 20.0, .ignored, false, 0, 2.0),
        (["ignored_noise", "silence"], "speaker.slash.fill", .gray, 0.0, 0.0, .ignored, false, 0, 2.5)

    ]
    
    // Helper to keep the main function clean
    private static func createAndCache(profile entry: (keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double), for label: String) -> SoundProfile {
        let p = SoundProfile(
            icon: entry.icon,
            color: entry.color,
            ceiling: entry.ceiling,
            maxRange: entry.maxRange,
            category: entry.category,
            canonicalLabel: entry.keywords.first ?? label,
            shouldSnapToRoad: entry.snaps,
            hapticCount: entry.haptics,
            cooldown: entry.cooldown          // ← NEW
        )
        queue.async(flags: .barrier) { lookupTable[label] = p }
        return p
    }
    
    static func classify(_ label: String) -> SoundProfile {
        let lowerLabel = label.lowercased()
        
        // 1. Check Hash Map First
        var cachedResult: SoundProfile?
        queue.sync { cachedResult = lookupTable[lowerLabel] }
        if let cached = cachedResult { return cached }
        
        // 2. SEARCH REGISTRY
        for entry in rawRegistry {
            if entry.keywords.contains(where: { lowerLabel == $0 }) {
                AppGlobals.doLog(message: "Found [\(lowerLabel)] in registry. Caching [\(entry)].", step: "SOUNDPROFILE_CLASSIFY")
                return createAndCache(profile: entry, for: lowerLabel)
            }
        }
        
        let msg = "No sound profile found for [\(lowerLabel)]. Using default \"waveform\"."
        AppGlobals.doLog(message: msg, step: "SOUNDPROFILE_CLASSIFY")
        
        // Fallback
        let fallback = SoundProfile(
            icon: "waveform",
            color: .gray,
            ceiling: 0.55,
            maxRange: 150.0,
            category: .unknown,
            canonicalLabel: label,
            shouldSnapToRoad: false,
            hapticCount: 0,
            cooldown: 1.5          // ← NEW fallback cooldown
        )
        
        queue.async(flags: .barrier) {
            lookupTable[lowerLabel] = fallback
        }
        
        return fallback
    }
}

// ... Rest of the HUD View code remains the same ...
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
        let recent = events.filter { now.timeIntervalSince($0.timestamp) < 10.0 }
        
        var dictionary: [String: SoundEvent] = [:]
        
        for event in recent {
            // Normalize the label for music so "🎵 Song A" and "🎵 Song B"
            // or raw "music" all compete for the same slot.
            let isMusic = event.threatLabel.lowercased().contains("music")
            let key = isMusic ? "music_king" : event.threatLabel
            
            if let existing = dictionary[key] {
                // Keep the one with the highest energy (the loudest/best signal)
                if event.energy > existing.energy {
                    dictionary[key] = event
                }
            } else {
                dictionary[key] = event
            }
        }
        
        // Return the values using your original sorting logic
        return dictionary.values.sorted(by: { $0.timestamp > $1.timestamp })
    }
    
    struct ThreatHUDItemInstance: View {
        var event: SoundEvent
        
        var body: some View {
            let profile = SoundProfile.classify(event.threatLabel)
            let displayLabel = event.threatLabel.replacingOccurrences(of: "_", with: " ").capitalized
            let color = profile.color
            
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .stroke(profile.color.opacity(Double(event.energy)), lineWidth: 3)
                        .frame(width: 54, height: 54)
                    
                    Image(systemName: profile.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: event.energy)
                    
                    Circle()
                        .trim(from: 0.0, to: 0.05)
                        .stroke(profile.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 62, height: 62)
                        .rotationEffect(.degrees(Double(event.bearing) - 90))
                }
                
                Text(displayLabel)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(color.opacity(1))
                    .lineLimit(1)
                    .frame(width: 50)
            }
        }
    }
}
