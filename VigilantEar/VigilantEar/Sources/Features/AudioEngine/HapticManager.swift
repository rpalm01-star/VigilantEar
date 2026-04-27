// HapticManager.swift
// VigilantEar

import Foundation
import CoreHaptics

@MainActor
class HapticManager {
    static let shared = HapticManager()
    
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
            engine?.stoppedHandler = { reason in
                AppGlobals.doLog(message: "Haptic Engine stopped: \(reason)", step: "HAPTIC_MANAGER")
            }
            engine?.resetHandler = { [weak self] in
                AppGlobals.doLog(message: "Restarting Haptic Engine...", step: "HAPTIC_MANAGER")
                try? self?.engine?.start()
            }
            try engine?.start()
        } catch {
            AppGlobals.doLog(message: "Failed to create Haptic Engine: \(error)", step: "HAPTIC_MANAGER")
        }
    }
    
    func trigger(count: Int, sessionID: UUID) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, count > 0 else { return }
        
        let now = Date()
        if let last = sessionCooldowns[sessionID], now.timeIntervalSince(last) < minimumObjectInterval {
            return
        }
        
        guard !isFiring else { return }
        isFiring = true
        sessionCooldowns[sessionID] = now
        
        Task {
            do {
                try await engine?.start()
                
                let pattern = try createHapticPattern(for: count)
                let player = try engine?.makePlayer(with: pattern)
                try player?.start(atTime: CHHapticTimeImmediate)
                
                AppGlobals.doLog(message: "🚨 Haptic triggered: \(count) pulses (emergency)", step: "HAPTIC_MANAGER")
                
            } catch {
                AppGlobals.doLog(message: "Haptic play failed: \(error)", step: "HAPTIC_MANAGER")
            }
            
            let delay = count >= 3 ? 1.2 : 0.4
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            isFiring = false
        }
    }
    
    // MARK: - Pattern Factory
    private func createHapticPattern(for count: Int) throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        
        switch count {
        case 3...Int.max:  // 🔥 MAX INTENSITY EMERGENCY (Amber Alert style)
            AppGlobals.doLog(message: "🚨 MAX EMERGENCY HAPTIC PATTERN", step: "HAPTIC_MANAGER")
            
            let maxIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let maxSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            
            // Sharp, urgent triple hit
            for i in 0..<3 {
                let hit = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [maxIntensity, maxSharpness],
                    relativeTime: Double(i) * 0.16
                )
                events.append(hit)
            }
            
            // Long, powerful rumble at the end
            let rumble = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.95),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                ],
                relativeTime: 0.65,
                duration: 1.1
            )
            events.append(rumble)
            
        case 2:
            // Double sharp hit
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.25))
            
        default:
            // Normal single tap
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        }
        
        return try CHHapticPattern(events: events, parameters: [])
    }
}
