import SwiftUI

enum ThreatCategory: String, Sendable {
    case emergency, vehicle, medium, quiet, animal, misc, unknown, music, ignored
}

struct SoundProfile {
    let icon: String
    let color: Color
    let ceiling: Double
    let maxRange: Double
    let category: ThreatCategory
    let canonicalLabel: String
    let shouldSnapToRoad: Bool
    let hapticCount: Int
    let cooldown: Double
    let originalLabel: String
    
    // THE NEW RADAR PHYSICS
    let minimumConfidence: Double
    let leadInTime: Double    // ⏳ Seconds the sound must exist BEFORE triggering UI
    let tailMemory: Double    // 👻 Seconds the sound stays on radar AFTER ML stops hearing it
    
    var isEmergency: Bool { return category == .emergency }
    var isMusic: Bool { return category == .music }
    var isVehicle: Bool { return category == .vehicle }
    
    var revealThreshold: Double {
        return minimumConfidence
    }
    
    private static var lookupTable: [String: SoundProfile] = [:]
    private static let queue = DispatchQueue(label: "com.VigilantEar.profileCache", attributes: .concurrent)
    
    // MARK: - THE REGISTRY
    // Tuple: (Keywords, Icon, Color, Ceiling, MaxRange, Category, Snaps, Haptics, Cooldown, minConf, leadInTime, tailMemory)
    
    private static let cuteAndPleasant: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = [
        (["microwave_oven"], "oven", .orange, 0.60, 80.0, .misc, false, 2, 1.2, 0.60, 0.5, 1.0),
        (["boiling"], "cup.and.saucer", .teal, 0.55, 60.0, .misc, false, 2, 1.2, 0.60, 0.5, 1.0),
        (["clock", "tick", "tick_tock"], "clock", .brown, 0.55, 100.0, .misc, false, 1, 1.5, 0.60, 1.0, 1.5),
        (["chime", "wind_chime"], "wind", .cyan, 0.50, 150.0, .misc, false, 1, 2.0, 0.60, 0.5, 2.0),
        (["singing_bowl"], "music.quarternote.3", .purple, 0.55, 120.0, .music, false, 1, 1.8, 0.50, 0.5, 2.0),
    ]
    
    private static let emergencyAndSafety: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = [
        (["siren", "ambulance_siren", "police_siren", "fire_engine_siren", "civil_defense_siren", "emergency_vehicle", "simulated_fire_truck"], "light.beacon.max.fill", .red, 0.80, 750.0, .emergency, true, 4, 0.4, 0.70, 0.5, 3.0),
        // 🚨 TRANSIENT EMERGENCY: Lead-In is 0.0, Tail is 4.0
        (["fireworks", "gunshot_gunfire", "artillery_fire", "firecracker", "eruption", "boom"], "fireworks", .red, 0.90, 1000.0, .emergency, false, 2, 0.8, 0.85, 0.0, 4.0),
        (["smoke_detector", "alarm_clock", "telephone_bell_ringing", "ringtone", "door_bell", "reverse_beeps", "beep"], "exclamationmark.triangle.fill", .red, 0.80, 150.0, .emergency, false, 3, 0.4, 0.65, 0.2, 2.0),
        (["knock", "person_running", "person_shuffling", "person_walking", "door_slam", "door_sliding"], "figure.walk.arrival", .red, 0.80, 150.0, .emergency, false, 2, 0.50, 0.60, 0.2, 2.0),
    ]
    
    private static let vehicles: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = [
        (["car", "car_passing_by", "race_car", "truck", "bus", "motorcycle", "traffic_noise", "engine", "engine_accelerating_revving", "engine_starting", "engine_idling", "engine_knocking", "vehicle_skidding"], "car.fill", .blue, 0.30, 500.0, .vehicle, true, 0, 0.1, 0.45, 0.5, 2.0),
        (["train_horn", "foghorn", "air_horn", "train_whistle", "car_horn"], "horn.fill", .blue, 0.60, 500.0, .medium, true, 0, 2.0, 0.60, 0.2, 2.0),
        (["train", "rail_transport", "railroad_car", "train_wheels_squealing", "subway_metro", "aircraft", "helicopter", "airplane", "boat_water_vehicle", "sailing", "rowboat_canoe_kayak", "motorboat_speedboat"], "tram.fill.tunnel", .blue, 0.15, 600.0, .ignored, false, 0, 0.8, 0.50, 1.0, 3.0),
        (["bicycle"], "bicycle", .blue, 0.40, 800.0, .medium, false, 0, 1.5, 0.50, 0.5, 1.5),
    ]
    
    private static let animalsAndNature: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = [
        (["dog", "dog_bark", "dog_howl", "dog_bow_wow", "dog_whimper", "dog_growl", "coyote_howl"], "dog.fill", .brown, 0.40, 150.0, .animal, false, 0, 2.2, 0.60, 0.4, 1.5),
        (["cat", "cat_purr", "cat_meow"], "cat.fill", .brown, 0.35, 40.0, .animal, false, 0, 2.2, 0.60, 0.4, 1.5),
        (["fowl", "bird", "bird_vocalization", "bird_chirp_tweet", "bird_squawk", "pigeon_dove_coo", "crow_caw", "owl_hoot", "bird_flapping", "chicken", "chicken_cluck", "rooster_crow", "turkey_gobble", "duck_quack", "goose_honk"], "bird.fill", .brown, 0.35, 60.0, .animal, false, 0, 2.2, 0.60, 0.4, 1.5),
        (["horse_clip_clop", "horse_neigh", "cow_moo", "pig_oink", "sheep_bleat", "lion_roar", "insect", "cricket_chirp", "mosquito_buzz", "fly_buzz", "bee_buzz", "frog", "frog_croak", "snake_hiss", "snake_rattle", "whale_vocalization", "elk_bugle"], "pawprint.fill", .brown, 0.40, 100.0, .animal, false, 0, 0.8, 0.60, 0.5, 1.5),
        (["wind_rustling_leaves"], "leaf.fill", .green, 0.45, 200.0, .misc, false, 0, 1.5, 0.55, 1.0, 1.5),
        (["wind", "wind_noise_microphone"], "wind", .teal, 0.30, 300.0, .ignored, false, 0, 1.5, 0.55, 1.0, 2.0),
        (["thunderstorm", "thunder", "water", "rain", "raindrop", "stream_burbling", "waterfall", "ocean", "sea_waves", "gurgling"], "cloud.heavyrain.fill", .blue, 0.35, 400.0, .misc, false, 0, 1.8, 0.60, 1.0, 2.0),
        (["fire", "fire_crackle"], "flame.fill", .orange, 0.50, 150.0, .misc, false, 0, 1.5, 0.60, 0.5, 1.5),
    ]
    
    private static let humanSounds: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = [
        (["speech", "shout", "yell", "battle_cry", "children_shouting", "screaming", "whispering", "laughter", "baby_laughter", "giggling", "snicker", "belly_laugh", "chuckle_chortle", "crying_sobbing", "baby_crying", "sigh", "chatter", "crowd", "babble", "clapping", "cheering", "applause", "booing", "finger_snapping"], "microphone.fill", .cyan, 0.55, 120.0, .medium, false, 0, 0.8, 0.55, 0.5, 1.5),
        (["telephone"], "phone.fill", .pink, 0.70, 150.0, .medium, true, 3, 0.4, 0.60, 0.2, 1.5),
    ]
    
    private static let household: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = [
        (["lawn_mower", "cutlery_silverware", "chopping_food", "frying_food", "blender", "water_tap_faucet", "bathtub_filling_washing", "hair_dryer", "drawer_open_close", "toothbrush", "vacuum_cleaner", "electric_shaver", "zipper"], "house.fill", .mint, 0.40, 40.0, .misc, false, 0, 1.6, 0.65, 0.8, 1.5),
        (["typing", "tap", "typewriter", "typing_computer_keyboard", "writing", "camera", "printer"], "keyboard", .mint, 0.35, 40.0, .misc, false, 0, 2.2, 0.65, 0.5, 1.5),
        (["door", "squeak", "keys_jangling", "coin_dropping", "scissors", "ratchet_and_pawl", "power_windows"], "door.left.hand.closed", .mint, 0.35, 30.0, .misc, false, 0, 1.6, 0.60, 0.2, 1.5),
        (["liquid_splashing", "liquid_sloshing", "liquid_squishing", "liquid_dripping", "liquid_trickle_dribble", "liquid_filling_container", "liquid_spraying", "water_pump", "underwater_bubbling", "whoosh_swoosh_swish", "thump_thud", "crushing", "crumpling_crinkling", "tearing", "click"], "drop.fill", .mint, 0.45, 50.0, .misc, false, 0, 2.2, 0.65, 0.5, 1.5),
        (["sewing_machine", "mechanical_fan", "air_conditioner"], "fan.fill", .gray, 0.20, 20.0, .ignored, false, 0, 1.6, 0.70, 1.0, 2.0),
        (["toilet_flush", "sink_filling_washing"], "toilet.fill", .white, 0.20, 20.0, .ignored, false, 0, 2.0, 0.70, 1.0, 2.0),
        (["wood_cracking", "power_tool", "saw", "hammer", "drill", "hedge_trimmer", "chopping_wood", "chainsaw"], "hammer.fill", .orange, 0.60, 120.0, .medium, false, 0, 1.2, 0.60, 0.5, 1.5),
        // 🚨 TRANSIENT EMERGENCY: Lead-In is 0.0, Tail is 3.0
        (["glass_clink", "glass_breaking"], "tear", .orange, 0.70, 100.0, .misc, false, 1, 1.4, 0.70, 0.0, 3.0),
    ]
    
    private static let musicAndEntertainment: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = [
        (["music", "singing", "choir_singing", "yodeling", "rapping", "humming", "whistling", "plucked_string_instrument", "guitar", "electric_guitar", "bass_guitar", "acoustic_guitar", "steel_guitar_slide_guitar", "guitar_tapping", "guitar_strum", "banjo", "sitar", "mandolin", "zither", "ukulele", "keyboard_musical", "piano", "electric_piano", "organ", "electronic_organ", "hammond_organ", "synthesizer", "harpsichord", "percussion", "drum_kit", "drum", "snare_drum", "bass_drum", "timpani", "tabla", "cymbal", "hi_hat", "tambourine", "rattle_instrument", "gong", "mallet_percussion", "marimba_xylophone", "glockenspiel", "vibraphone", "steelpan", "orchestra", "brass_instrument", "french_horn", "trumpet", "trombone", "bowed_string_instrument", "violin_fiddle", "cello", "double_bass", "wind_instrument", "flute", "saxophone", "clarinet", "oboe", "bassoon", "harp", "bell", "church_bell", "bicycle_bell", "cowbell", "tuning_fork", "harmonica", "accordion", "bagpipes", "didgeridoo", "shofar", "theremin", "disc_scratching"], "music.quarternote.3", .purple, 0.55, 150.0, .music, false, 0, 0.8, 0.45, 0.5, 2.0),
    ]
    
    private static let sports: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = [
        (["skateboard", "playing_badminton", "playing_hockey", "playing_squash", "playing_table_tennis", "playing_tennis", "playing_volleyball", "rope_skipping", "scuba_diving", "skiing", "basketball_bounce", "slap_smack", "bowling_impact"], "figure.run", .mint, 0.40, 80.0, .misc, false, 0, 1.5, 0.60, 0.2, 1.5),
    ]
    
    private static let ignored: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = [
        (["breathing", "snoring", "gasp", "cough", "sneeze", "nose_blowing", "chewing", "biting", "gargling", "burp", "hiccup", "slurp"], "lungs.fill", .gray, 0.20, 20.0, .ignored, false, 0, 2.0, 0.80, 1.0, 2.0),
        (["silence"], "speaker.slash.fill", .gray, 0.0, 0.0, .ignored, false, 0, 1.5, 0.80, 1.0, 2.0),
    ]
    
    private static let rawRegistry: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = {
        var all: [(keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double)] = []
        all.append(contentsOf: cuteAndPleasant)
        all.append(contentsOf: emergencyAndSafety)
        all.append(contentsOf: vehicles)
        all.append(contentsOf: animalsAndNature)
        all.append(contentsOf: humanSounds)
        all.append(contentsOf: household)
        all.append(contentsOf: musicAndEntertainment)
        all.append(contentsOf: sports)
        all.append(contentsOf: ignored)
        return all
    }()
    
    private static func createAndCache(profile entry: (keywords: [String], icon: String, color: Color, ceiling: Double, maxRange: Double, category: ThreatCategory, snaps: Bool, haptics: Int, cooldown: Double, minConf: Double, leadIn: Double, tail: Double), for label: String) -> SoundProfile {
        
        let p = SoundProfile(
            icon: entry.icon,
            color: entry.color,
            ceiling: entry.ceiling,
            maxRange: entry.maxRange,
            category: entry.category,
            canonicalLabel: entry.keywords.first ?? label,
            shouldSnapToRoad: entry.snaps,
            hapticCount: entry.haptics,
            cooldown: entry.cooldown,
            originalLabel: label,
            minimumConfidence: entry.minConf,
            leadInTime: entry.leadIn,
            tailMemory: entry.tail
        )
        queue.async(flags: .barrier) { lookupTable[label] = p }
        return p
    }
    
    static func classify(_ label: String) -> SoundProfile {
        let lowerLabel = label.lowercased()
        
        var cachedResult: SoundProfile?
        queue.sync { cachedResult = lookupTable[lowerLabel] }
        if let cached = cachedResult { return cached }
        
        for entry in rawRegistry {
            if entry.keywords.contains(lowerLabel) {
                return createAndCache(profile: entry, for: lowerLabel)
            }
        }
        
        AppGlobals.doLog(message: "⚠️ UNEXPECTED: Sound label [\(lowerLabel)] was NOT in registry.",
                         step: "SOUNDPROFILE_CLASSIFY",
                         logName: AppGlobals.logDataStoreName,
                         isError: true)
        
        let fallback = SoundProfile(
            icon: "waveform",
            color: .gray,
            ceiling: 0.55,
            maxRange: 150.0,
            category: .unknown,
            canonicalLabel: label,
            shouldSnapToRoad: false,
            hapticCount: 0,
            cooldown: 1.5,
            originalLabel: lowerLabel,
            minimumConfidence: 0.80,
            leadInTime: 0.5,
            tailMemory: 2.0
        )
        
        queue.async(flags: .barrier) {
            lookupTable[lowerLabel] = fallback
        }
        
        return fallback
    }
}
