import Foundation
import AVFoundation
import CoreLocation
import UserNotifications // 🚨 NEW: Required for the alert permission

@Observable
@MainActor // 🚨 Added MainActor to ensure SwiftUI updates safely
class PermissionsManager {
    var isMicrophoneAuthorized = false
    var isLocationAuthorized = false
    var areNotificationsAuthorized = false // 🚨 NEW
    
    /// Requests all necessary hardware access for VigilantEar
    func requestAllPermissions() async {
        await requestMicrophoneAccess()
        requestLocationAccess()
        await requestNotificationAccess() // 🚨 NEW
    }
    
    private func requestMicrophoneAccess() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .notDetermined:
            isMicrophoneAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        case .authorized:
            isMicrophoneAuthorized = true
        default:
            isMicrophoneAuthorized = false
        }
    }
    
    private func requestLocationAccess() {
        let locationManager = CLLocationManager()
        // This triggers the popup defined by your Info.plist strings
        locationManager.requestWhenInUseAuthorization()
        
        let status = locationManager.authorizationStatus
        isLocationAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
    }
    
    // MARK: - New Notification Gate
    private func requestNotificationAccess() async {
        let center = UNUserNotificationCenter.current()
        
        do {
            // We request alert (visual), badge (red dot), and sound (even though we rely on haptics, it's good practice)
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            self.areNotificationsAuthorized = granted
            
            AppGlobals.doLog(message: "Push Notifications Granted: \(granted)", step: "PERMISSIONS")
            
        } catch {
            self.areNotificationsAuthorized = false
            AppGlobals.doLog(message: "Push Notification Error: \(error.localizedDescription)", step: "PERMISSIONS", isError: true)
        }
    }
}
