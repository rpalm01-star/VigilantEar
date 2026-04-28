import Foundation
import UserNotifications

@MainActor
class NotificationManager {
    static let shared = NotificationManager()
    
    // Throttle: Don't send another push notification if we already sent one recently
    private var lastNotificationTime: Date = .distantPast
    private let notificationCooldown: TimeInterval = 15.0 // Wait 15 seconds between push alerts
    
    private init() {}
    
    // Call this when the app launches or during onboarding
    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                AppGlobals.doLog(message: "Push Notification Error: \(error.localizedDescription)", step: "NOTIFICATIONS", isError: true)
            } else {
                AppGlobals.doLog(message: "Push Notifications Granted: \(granted)", step: "NOTIFICATIONS")
            }
        }
    }
    
    // Call this from the pipeline when an emergency hits
    func sendEmergencyAlert(for label: String) {
        let now = Date()
        
        // 1. Check the throttle
        guard now.timeIntervalSince(lastNotificationTime) > notificationCooldown else { return }
        lastNotificationTime = now
        
        // 2. Format the text for human eyes
        let displayLabel = label.replacingOccurrences(of: "_", with: " ").capitalized
        
        // 3. Build the payload
        let content = UNMutableNotificationContent()
        content.title = "🚨 \(displayLabel) Detected"
        content.body = "Emergency sound tracking active."
        content.sound = .default // Optional, but good practice
        
        // 🚨 THE MAGIC BYPASS: This punches through "Do Not Disturb" / "Sleep" modes
        content.interruptionLevel = .timeSensitive
        
        // 4. Fire the trigger immediately
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppGlobals.doLog(message: "Failed to send alert: \(error.localizedDescription)", step: "NOTIFICATIONS", isError: true)
            }
        }
    }
}