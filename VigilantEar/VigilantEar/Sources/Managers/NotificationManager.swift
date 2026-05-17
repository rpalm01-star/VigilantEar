import Foundation
import UserNotifications
import SwiftUI

struct ActiveAlert: Codable {
    let id: String
    let label: String
    let firedAt: Date
    let expiresAt: Date
}

@MainActor
class NotificationManager {
    
    // MARK: - Master Push Notification Control
    private var isPushNotificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "pushNotificationsMasterEnabled")
    }
    
    // MARK: - Individual toggles (mirrored from PreferencesPanelView)
    @AppStorage("alert_alarm") private var alarmEnabled = false
    @AppStorage("alert_knock") private var knockEnabled = false
    @AppStorage("alert_person") private var personEnabled = false
    @AppStorage("alert_nws") private var nwsEnabled = false
    @AppStorage("alert_siren") private var sirenEnabled = false
    
    // Configuration
    private let throttleMinutes: Double = 0.25
    private let alertLifespanMinutes: Double = 2.0
    
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    private var persistedAlerts: [String: ActiveAlert] = [:] {
        didSet { saveToDisk() }
    }
    
    public init() {
        loadFromDisk()
        startCleanupTask()
    }
    
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(persistedAlerts) {
            UserDefaults.standard.set(data, forKey: AppGlobals.localPersistenceIdentifier)
        }
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: AppGlobals.localPersistenceIdentifier),
           let savedAlerts = try? JSONDecoder().decode([String: ActiveAlert].self, from: data) {
            self.persistedAlerts = savedAlerts
            AppGlobals.doLog(message: "💾 Loaded \(savedAlerts.count) active alerts from disk.", step: "NotificationManager.loadFromDisk")
        }
    }
    
    // MARK: - Core Logic
    
    func sendEmergencyAlert(for inLabel: String) {
        // 1. Master toggle check
        guard isPushNotificationsEnabled else {
            AppGlobals.doLog(message: "🚫 Master push notifications disabled. Skipping '\(inLabel)'", step: "NotificationManager")
            return
        }
        
        // 2. Individual toggle check for this specific alert type
        let outLabel = inLabel.formatLabelForAlert
        guard shouldSendForType(outLabel) else {
            AppGlobals.doLog(message: "🚫 Individual toggle disabled for '\(outLabel)'. Skipping banner.", step: "NotificationManager")
            return
        }
        
        let now = Date()
        
        // Throttle check
        if let existingAlert = persistedAlerts[outLabel] {
            let minutesSinceLast = now.timeIntervalSince(existingAlert.firedAt) / 60.0
            if minutesSinceLast < throttleMinutes {
                AppGlobals.doLog(message: "⏳ '\(outLabel)' throttled for another \(String(format: "%.1f", throttleMinutes - minutesSinceLast))m.", step: "NotificationManager")
                return
            }
        }
        
        let alertID = UUID().uuidString
        
        persistedAlerts[outLabel] = ActiveAlert(
            id: alertID,
            label: outLabel,
            firedAt: now,
            expiresAt: now.addingTimeInterval(alertLifespanMinutes * 60.0)
        )
        
        let appState = UIApplication.shared.applicationState
        guard appState != .active else {
            AppGlobals.doLog(message: "📱 App is active. Suppressed banner for '\(outLabel)'.", step: "NotificationManager")
            return
        }
        
        // Build localized title/body (unchanged from your original code)
        var detectedLocalized = AppGlobals.detected
        detectedLocalized.locale = Locale(identifier: preferredLanguage)
        let detectedLocalizedOut = String(localized: detectedLocalized)
        
        var emergencyAlertTextLocalized = AppGlobals.emergencyAlertText
        emergencyAlertTextLocalized.locale = Locale(identifier: preferredLanguage)
        let emergencyAlertTextLocalizedOut = String(localized: emergencyAlertTextLocalized)
        
        var c: LocalizedStringResource = LocalizedStringResource(String.LocalizationValue(inLabel.lowercased()))
        c.locale = Locale(identifier: preferredLanguage)
        let outLabelLocalized = String(localized: c).capitalized
        
        let titleLocalized = "🚨 \(outLabelLocalized) \(detectedLocalizedOut)"
        
        let content = UNMutableNotificationContent()
        content.title = titleLocalized
        content.body = emergencyAlertTextLocalizedOut
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        
        let request = UNNotificationRequest(identifier: alertID, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppGlobals.doLog(message: "📲 Failed to send alert: \(error.localizedDescription)", step: "NotificationManager", isError: true)
            } else {
                AppGlobals.doLog(message: "📲 Pushed iOS banner for: \(outLabel)", step: "NotificationManager")
            }
        }
    }
    
    // MARK: - Individual toggle checker
    private func shouldSendForType(_ label: String) -> Bool {
        let l = label.uppercased()
        if l.contains("SIREN") { return sirenEnabled }
        if l.contains("ALARM") { return alarmEnabled }
        if l.contains("KNOCK") || l.contains("DOORBELL") { return knockEnabled }
        if l.contains("PERSON") { return personEnabled }
        if l.contains("NWS") || l.contains("WEATHER") { return nwsEnabled }
        
        // Fallback: allow unknown types (you can tighten this later)
        return true
    }
    
    // MARK: - Cleanup (unchanged)
    private func startCleanupTask() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(30))
                let now = Date()
                var expiredIDs: [String] = []
                
                for (label, alert) in persistedAlerts {
                    if now >= alert.expiresAt {
                        expiredIDs.append(alert.id)
                        persistedAlerts[label] = nil
                    }
                }
                if !expiredIDs.isEmpty {
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: expiredIDs)
                }
            }
        }
    }
}

extension String {
    var formatLabelForAlert: String {
        let firstPart = split(separator: "_").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? self
        guard !firstPart.isEmpty else { return String.empty }
        return firstPart.count > 3 ? firstPart.capitalized : firstPart.uppercased()
    }
}
