import Foundation
import CoreHaptics

@MainActor
class HapticManager {
    static let shared = HapticManager()
    
    // The Core Haptics engine that bypasses UIKit restrictions
    private var engine: CHHapticEngine?
    
    private var isFiring = false
    private var sessionCooldowns: [UUID: Date] = [:]
    private let minimumObjectInterval: TimeInterval = 6.0
    
    init() {
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            
            // These handlers reboot the engine if the system kills it (e.g., an incoming phone call)
            engine?.stoppedHandler = { reason in
                AppGlobals.doLog(message: "Haptic Engine stopped: \(reason)", step: "HAPTIC_MANAGER")
            }
            engine?.resetHandler = { [weak self] in
                AppGlobals.doLog(message: "Restarting Haptic Engine...", step: "HAPTIC_MANAGER")
                do { try self?.engine?.start() } catch { }
            }
            
            try engine?.start()
        } catch {
            AppGlobals.doLog(message: "Failed to create Haptic Engine: \(error)", step: "HAPTIC_MANAGER")
        }
    }
    
    func trigger(count: Int, sessionID: UUID) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        let now = Date()
        
        // 1. THE OBJECT COOLDOWN
        if let lastVibrated = sessionCooldowns[sessionID],
           now.timeIntervalSince(lastVibrated) < minimumObjectInterval {
            // AppGlobals.doLog(message: "⚠️ Haptic manager is cooling down. Request ignored.", step: "HAPTIC_MANAGER")
            return
        }
        
        // 2. THE HARDWARE GATEKEEPER
        guard !isFiring && count > 0 else { return }
        
        isFiring = true
        sessionCooldowns[sessionID] = now
        
        // 3. BUILD AND PLAY THE PATTERN
        do {
            // Wake the engine if it went to sleep
            try engine?.start()
            
            var events: [CHHapticEvent] = []
            
            if count >= 3 {
                // --- 🚨 EMERGENCY: 3 Heavy Pulses ---
                AppGlobals.doLog(message: "✅ Heavy impact requested from haptic manager", step: "HAPTIC_MANAGER")
                
                // Maximum intensity and sharpness
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                
                // Schedule 3 precise hits, 0.15 seconds apart
                for i in 0..<3 {
                    let event = CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [intensity, sharpness],
                        relativeTime: Double(i) * 0.15 // Automatically spaces them out!
                    )
                    events.append(event)
                }
            } else {
                // --- 🚗 STANDARD: 1 Light Pulse ---
                AppGlobals.doLog(message: "✅ Light impact requested from haptic manager", step: "HAPTIC_MANAGER")
                
                // Lower intensity and softer sharpness for a "tap" feel
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                
                let event = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: 0
                )
                events.append(event)
            }
            
            // Hand the track to the Taptic Engine
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
            
        } catch {
            AppGlobals.doLog(message: "Failed to play haptic pattern: \(error)", step: "HAPTIC_MANAGER")
        }
        
        // Cleanup memory and reset the firing gate
        Task {
            let delay = count >= 3 ? 450_000_000 : 200_000_000
            try? await Task.sleep(nanoseconds: UInt64(delay))
            
            isFiring = false
            sessionCooldowns = sessionCooldowns.filter { now.timeIntervalSince($0.value) < 60 }
        }
    }
}
