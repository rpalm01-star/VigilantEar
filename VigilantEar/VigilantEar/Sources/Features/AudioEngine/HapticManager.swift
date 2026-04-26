import UIKit

@MainActor
class HapticManager {
    static let shared = HapticManager()
    
    private var isFiring = false
    
    // We use Impact generators for more "physical" feel that ignores the silent switch
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    
    private var sessionCooldowns: [UUID: Date] = [:]
    private let minimumObjectInterval: TimeInterval = 6.0
    
    func trigger(count: Int, sessionID: UUID) {
        let now = Date()
        
        // 1. THE OBJECT COOLDOWN
        if let lastVibrated = sessionCooldowns[sessionID],
           now.timeIntervalSince(lastVibrated) < minimumObjectInterval {
            AppGlobals.doLog(
                message: "⚠️ Haptic manager is cooling down. Request ignored.",
                step: "HAPTIC_MANAGER"
            )
            return
        }
        
        // 2. THE HARDWARE GATEKEEPER
        guard !isFiring && count > 0 else { return }
        
        isFiring = true
        sessionCooldowns[sessionID] = now
        
        // 3. PREPARE THE HARDWARE (Crucial for zero-latency)
        if count >= 3 { heavyImpact.prepare() } else { lightImpact.prepare() }
        
        Task {
            if count >= 3 {
                // Triple heavy impact for emergencies (Fire/Sirens/Footsteps)
                for _ in 0..<3 {
                    heavyImpact.impactOccurred()
                    AppGlobals.doLog(
                        message: "✅ Heavy impact requested from haptic manager",
                        step: "HAPTIC_MANAGER"
                    )
                    // 0.1s is the "sweet spot" for human perception of distinct pulses
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            } else {
                // Single light pulse for cars/ambient
                lightImpact.impactOccurred()
                AppGlobals.doLog(
                    message: "✅ Light impact requested from haptic manager",
                    step: "HAPTIC_MANAGER"
                )
                // Small lockout to prevent "buzzing" from rapid overlapping events
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            
            isFiring = false
            sessionCooldowns = sessionCooldowns.filter { now.timeIntervalSince($0.value) < 60 }
        }
    }
}
