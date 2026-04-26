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
    let cooldown: Double          // ← Recommended debounce time in seconds
    
    // Computed Properties for Logic Gates
    var isEmergency: Bool { return category == .emergency }
    var isVehicle: Bool { return category == .vehicle }
    var revealThreshold: Double {
        if isEmergency { return 0.40 }
        if isVehicle { return 0.45 }
        if canonicalLabel == "music" { return 0.45 }
        return 0.60 // Default for animals, misc, etc.
    }

    // --- THE THREAD-SAFE CONCURRENT CACHE ---
    private static var lookupTable: [String: SoundProfile] = [:]
    private static let queue = DispatchQueue(label: "com.VigilantEar.profileCache", attributes: .concurrent)
    
    // 1. THE EXHAUSTIVE EXACT-MATCH REGISTRY
    // Tuple: (Keywords, Icon, Color, Ceiling, MaxRange, Category, Snaps, Haptics, Cooldown)
    private static let rawRegistry: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double)] = [
        
        // --- 🚨 EMERGENCY / SIRENS (High Priority) ---
        (["siren", "ambulance_siren", "police_siren", "fire_engine_siren", "civil_defense_siren", "foghorn", "emergency_vehicle", "simulated_fire_truck"], "light.beacon.max.fill", .red, 0.80, 1000.0, .emergency, true, 3, 1.1),
        
        // --- ⚠️ THREATS / DANGER (High Priority) ---
        (["gunshot_gunfire", "artillery_fire", "fireworks", "firecracker", "eruption", "boom"], "shriker.fill", .red, 0.90, 1000.0, .emergency, false, 2, 1.2),
        
        // --- 👣 PERSONAL SAFETY / APPROACH (High Priority for Safety) ---
        (["person_running", "person_shuffling", "person_walking", "knock", "door_slam", "door_sliding"], "figure.walk.arrival", .red, 0.45, 60.0, .emergency, false, 2, 1.1),
        
        // --- 🔔 CRITICAL ALERTS ---
        (["smoke_detector", "alarm_clock", "telephone_bell_ringing", "ringtone", "door_bell", "reverse_beeps", "beep"], "exclamationmark.triangle.fill", .red, 0.60, 100.0, .emergency, false, 2, 1.2),
        
        // --- 🚗 VEHICLES (Important but standard) ---
        (["air_horn", "train_horn", "train_whistle", "car_horn"], "horn.fill", .purple, 0.80, 1000.0, .emergency, true, 1, 1.2),
        (["car", "car_passing_by", "race_car", "truck", "bus", "motorcycle", "traffic_noise", "engine", "engine_accelerating_revving", "engine_starting", "engine_idling", "engine_knocking", "vehicle_skidding"], "car.fill", .blue, 0.30, 500.0, .vehicle, true, 0, 1.2),
        (["rail_transport", "train", "railroad_car", "train_wheels_squealing", "subway_metro", "aircraft", "helicopter", "airplane", "boat_water_vehicle", "sailing", "rowboat_canoe_kayak", "motorboat_speedboat"], "tram.fill.tunnel", .blue, 0.15, 600.0, .ignored, false, 0, 2.2),
        
        // --- 🛠️ WORK / TOOLS ---
        (["hammer", "saw", "power_tool", "drill", "hedge_trimmer", "chopping_wood", "wood_cracking", "lawn_mower", "chainsaw"], "hammer.fill", .orange, 0.60, 100.0, .medium, false, 0, 1.4),
        
        // --- 🎵 THE MEGA MUSIC FUNNEL (Informational) ---
        (["music", "singing", "choir_singing", "yodeling", "rapping", "humming", "whistling", "plucked_string_instrument", "guitar", "electric_guitar", "bass_guitar", "acoustic_guitar", "steel_guitar_slide_guitar", "guitar_tapping", "guitar_strum", "banjo", "sitar", "mandolin", "zither", "ukulele", "keyboard_musical", "piano", "electric_piano", "organ", "electronic_organ", "hammond_organ", "synthesizer", "harpsichord", "percussion", "drum_kit", "drum", "snare_drum", "bass_drum", "timpani", "tabla", "cymbal", "hi_hat", "tambourine", "rattle_instrument", "gong", "mallet_percussion", "marimba_xylophone", "glockenspiel", "vibraphone", "steelpan", "orchestra", "brass_instrument", "french_horn", "trumpet", "trombone", "bowed_string_instrument", "violin_fiddle", "cello", "double_bass", "wind_instrument", "flute", "saxophone", "clarinet", "oboe", "bassoon", "harp", "bell", "church_bell", "bicycle_bell", "cowbell", "tuning_fork", "chime", "wind_chime", "harmonica", "accordion", "bagpipes", "didgeridoo", "shofar", "theremin", "singing_bowl", "disc_scratching"], "music.quarternote.3", .purple, 0.55, 150.0, .medium, false, 0, 2.2),
        
        // --- 🗣️ HUMAN VOICE & INTERACTION ---
        (["speech", "shout", "yell", "battle_cry", "children_shouting", "screaming", "whispering", "laughter", "baby_laughter", "giggling", "snicker", "belly_laugh", "chuckle_chortle", "crying_sobbing", "baby_crying", "sigh", "chatter", "crowd", "babble", "clapping", "cheering", "applause", "booing", "finger_snapping"], "person.wave.2.fill", .cyan, 0.55, 120.0, .medium, false, 0, 1.4),
        
        // --- 🐶 ANIMALS ---
        (["dog", "dog_bark", "dog_howl", "dog_bow_wow", "dog_growl", "dog_whimper", "coyote_howl"], "dog.fill", .brown, 0.40, 150.0, .animal, false, 0, 1.9),
        (["cat", "cat_purr", "cat_meow"], "cat.fill", .brown, 0.35, 40.0, .animal, false, 0, 1.9),
        (["bird", "bird_vocalization", "bird_chirp_tweet", "bird_squawk", "pigeon_dove_coo", "crow_caw", "owl_hoot", "bird_flapping", "fowl", "chicken", "chicken_cluck", "rooster_crow", "turkey_gobble", "duck_quack", "goose_honk"], "bird.fill", .brown, 0.35, 60.0, .animal, false, 0, 1.8),
        (["horse_clip_clop", "horse_neigh", "cow_moo", "pig_oink", "sheep_bleat", "lion_roar", "insect", "cricket_chirp", "mosquito_buzz", "fly_buzz", "bee_buzz", "frog", "frog_croak", "snake_hiss", "snake_rattle", "whale_vocalization", "elk_bugle"], "pawprint.fill", .brown, 0.40, 100.0, .animal, false, 0, 1.9),
        
        // --- 💧 NATURE & ELEMENTS ---
        (["wind", "wind_rustling_leaves", "wind_noise_microphone", "thunderstorm", "thunder", "water", "rain", "raindrop", "stream_burbling", "waterfall", "ocean", "sea_waves", "gurgling", "fire", "fire_crackle"], "leaf.arrow.triangle.circlepath", .teal, 0.30, 300.0, .medium, false, 0, 1.5),
        
        // --- 🏠 DOMESTIC / INTERIOR / MISC ---
        (["dishes_pots_pans", "cutlery_silverware", "chopping_food", "frying_food", "microwave_oven", "blender", "water_tap_faucet", "sink_filling_washing", "bathtub_filling_washing", "hair_dryer", "toilet_flush", "toothbrush", "vacuum_cleaner", "electric_shaver"], "house.fill", .mint, 0.40, 40.0, .misc, false, 0, 1.6),
        (["typing", "typewriter", "typing_computer_keyboard", "writing", "camera", "printer", "clock", "tick", "tick_tock", "telephone"], "keyboard", .mint, 0.35, 40.0, .misc, false, 0, 1.6),
        (["drawer_open_close", "door", "tap", "squeak", "zipper", "keys_jangling", "coin_dropping", "scissors", "ratchet_and_pawl", "power_windows"], "door.left.hand.closed", .mint, 0.35, 30.0, .misc, false, 0, 1.6),
        (["glass_clink", "glass_breaking", "liquid_splashing", "liquid_sloshing", "liquid_squishing", "liquid_dripping", "liquid_pouring", "liquid_trickle_dribble", "liquid_filling_container", "liquid_spraying", "water_pump", "boiling", "underwater_bubbling", "whoosh_swoosh_swish", "thump_thud", "crushing", "crumpling_crinkling", "tearing", "click"], "drop.fill", .mint, 0.35, 30.0, .misc, false, 0, 1.6),
        (["sewing_machine", "mechanical_fan", "air_conditioner"], "fanblades.fill", .gray, 0.20, 20.0, .ignored, false, 0, 2.0),
        
        // --- ⚽️ SPORTS & RECREATION ---
        (["bicycle", "skateboard", "basketball_bounce", "slap_smack", "bowling_impact", "playing_badminton", "playing_hockey", "playing_squash", "playing_table_tennis", "playing_tennis", "playing_volleyball", "rope_skipping", "scuba_diving", "skiing"], "figure.run", .mint, 0.40, 80.0, .misc, false, 0, 1.5),
        
        // --- 💤 BIOLOGICAL / IGNORED ---
        (["breathing", "snoring", "gasp", "cough", "sneeze", "nose_blowing", "chewing", "biting", "gargling", "burp", "hiccup", "slurp"], "lungs.fill", .gray, 0.20, 20.0, .ignored, false, 0, 2.0),
        (["silence"], "speaker.slash.fill", .gray, 0.0, 0.0, .ignored, false, 0, 2.5)
    ]
    
    // Helper to keep the main function clean
    private static func createAndCache(profile entry: (keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double), for label: String) -> SoundProfile {
        let p = SoundProfile(
            icon: entry.icon,
            color: entry.color,
            ceiling: entry.ceiling,
            maxRange: entry.maxRange,
            category: entry.category,
            canonicalLabel: entry.keywords.first ?? label, // The first keyword is the primary canonical label
            shouldSnapToRoad: entry.snaps,
            hapticCount: entry.haptics,
            cooldown: entry.cooldown
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
        
        // 2. STRICT EXACT MATCH SEARCH
        for entry in rawRegistry {
            // Using array `.contains` for strict string equality against elements (NOT string substring contains)
            if entry.keywords.contains(lowerLabel) {
                // AppGlobals.doLog(message: "Found [\(lowerLabel)] in registry. Caching.", step: "SOUNDPROFILE_CLASSIFY")
                return createAndCache(profile: entry, for: lowerLabel)
            }
        }
        
        let msg = "No exact profile found for [\(lowerLabel)]. Using default \"waveform\"."
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
            cooldown: 1.5
        )
        
        queue.async(flags: .barrier) {
            lookupTable[lowerLabel] = fallback
        }
        
        return fallback
    }
    
}
