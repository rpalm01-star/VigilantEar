// DebugSimulationManager.swift
// VigilantEar
//
// Created by Robert Palmer on 5/9/26.
//

import Foundation
import SwiftUI
import CoreLocation

@Observable
class DebugSimulationManager {
    
    public var isEmergencySimulationRunning: Bool = false

    init() {
        UserDefaults.standard.register(defaults: [
            "alert_nws": true,
            "alert_knock": true,
            "alert_person": true,
            "alert_alarm": true,
            "alert_siren": true
        ])
        AppGlobals.doLog(message: "🧪 Initialized", step: "DebugSimulationManager.init")
    }
    
    deinit {
        AppGlobals.doLog(message: "🧪 Deinitialized", step: "DebugSimulationManager.deinit")
    }
    
    // MARK: - Alert Preferences (synced from @AppStorage)
    private func isAlertEnabled(key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
    
    public func handleDoubleTap() {
        AppGlobals.doLog(message: "🌀 Double-tap detected: isDebugDevice: \(AppGlobals.isDebugDevice), isEmergencySimulationRunning: \(isEmergencySimulationRunning)")
        guard AppGlobals.isDebugDevice else { return }
        guard !isEmergencySimulationRunning else { return }
        AppGlobals.doLog(message: "✅ Double-tap accepted: starting emergency simulation", step: "DebugHUD.handleDoubleTap")
        startSimulation()
        scheduleBackgroundSimulations()
    }
    
    private func startSimulation() {
        isEmergencySimulationRunning = true
    }
    
    private func isSimulationRunning() -> Bool {
        return isEmergencySimulationRunning
    }
    
    private func stopSimulation() {
        isEmergencySimulationRunning = false
    }
    
    // Call this from your debugHUD
    public func scheduleBackgroundSimulations() {
        AppGlobals.doLog(message: "🧪 Scheduling staggered background simulations...", step: "DebugSimulationManager")
        let delaySeconds = 3.0
        
        Task {
            
            // Optional: A small initial delay before the chaos begins
            try? await Task.sleep(for: .seconds(3))
            
            AppGlobals.doLog(message: "🧪 alert_nws enabled? \(isAlertEnabled(key: "alert_nws"))", step: "DebugSimulationManager")
            if isAlertEnabled(key: "alert_nws") {
                triggerNWSBroadcast()
                try? await Task.sleep(for: .seconds(delaySeconds))
            }
            
            AppGlobals.doLog(message: "🧪 alert_knock enabled? \(isAlertEnabled(key: "alert_knock"))", step: "DebugSimulationManager")
            if isAlertEnabled(key: "alert_knock") {
                triggerSoundProfileMock(label: "knock")
                try? await Task.sleep(for: .seconds(delaySeconds))
            }
            
            AppGlobals.doLog(message: "🧪 alert_person enabled? \(isAlertEnabled(key: "alert_person"))", step: "DebugSimulationManager")
            if isAlertEnabled(key: "alert_person") {
                triggerSoundProfileMock(label: "person")
                try? await Task.sleep(for: .seconds(delaySeconds))
            }
            
            AppGlobals.doLog(message: "🧪 alert_alarm enabled? \(isAlertEnabled(key: "alert_alarm"))", step: "DebugSimulationManager")
            if isAlertEnabled(key: "alert_alarm") {
                triggerSoundProfileMock(label: "alarm")
                try? await Task.sleep(for: .seconds(delaySeconds))
            }
            
            AppGlobals.doLog(message: "🧪 alert_siren enabled? \(isAlertEnabled(key: "alert_siren"))", step: "DebugSimulationManager")
            if isAlertEnabled(key: "alert_siren") {
                triggerSoundProfileMock(label: "siren")
                try? await Task.sleep(for: .seconds(delaySeconds))
            }
            
            // When the staggered queue is finally empty, update the UI.
            await MainActor.run {
                AppGlobals.doLog(message: "🧪 stopping simulation.", step: "DebugSimulationManager")
                stopSimulation()
            }
        }
    }
    
    // MARK: - Your Internal Pipelines
    
    private func triggerNWSBroadcast() {
        AppGlobals.doLog(message: "🧪 Injecting mock event: NWS Broadcast", step: "DebugSimulationManager.triggerNWSBroadcast")
        
        var currentLocation: CLLocation? = DependencyContainer.shared.microphoneManager.currentLocation
        if currentLocation == nil {
            currentLocation = CLLocation(latitude: 32.7767, longitude: -117.1561)
        }
        
        let lat = currentLocation!.coordinate.latitude
        let lon = currentLocation!.coordinate.longitude
        let offset = 0.001   // ~350–400 feet in each direction → very tight around the user
        
        // Coffee cup polygon — handle now attached LOWER on the body (more realistic)
        let relativePoints: [(Double, Double)] = [
            (-0.55, -0.36), // 1. Bottom left
            (-0.55,  0.36), // 2. Bottom right
            (-0.37,  0.42), // 3. Lower right body
            (-0.20,  0.48), // 4. Lower handle attach
            (-0.04,  0.80), // 5. Handle lower curve
            ( 0.13,  0.90), // 6. Handle middle (widest)
            ( 0.27,  0.76), // 7. Handle upper curve
            ( 0.29,  0.52), // 8. UPPER HANDLE ATTACHMENT — now clearly below rim
            ( 0.48,  0.47), // 9. Top right rim
            ( 0.48, -0.47), // 10. Top left rim
            ( 0.35, -0.46), // 11. Upper left body
            (-0.38, -0.43), // 12. Lower left body
        ]
        
        let polygonStr = relativePoints.map { (relY, relX) in
            let pointLat = lat + relY * offset
            let pointLon = lon + relX * offset
            return "\(pointLat),\(pointLon)"
        }.joined(separator: " ") + " " + "\(lat + relativePoints[0].0 * offset),\(lon + relativePoints[0].1 * offset)"  // explicit close
        
        let langCode = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "en"
        var localizedAlert = AppGlobals.fakeCAPAlertText
        localizedAlert.locale = Locale(identifier: langCode)
        let translatedText = String(localized: localizedAlert)
        
        let mockXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:cap="urn:oasis:names:tc:emergency:cap:1.1">
            <entry>
                <cap:event>\(translatedText)</cap:event>
                <headline>\(translatedText)</headline>
                <cap:polygon>\(polygonStr)</cap:polygon>
            </entry>
        </feed>
        """
        
        guard let data = mockXML.data(using: .utf8) else { return }
        
        DependencyContainer.shared.capAlertManager.injectMockFeed(xmlData: data, timeoutInSeconds: 15)
        DependencyContainer.shared.notificationManager.sendEmergencyAlert(for: "nws_alert")
    }
    
    private func triggerSoundProfileMock(label: String) {
        AppGlobals.doLog(message: "🧪 Injecting mock event: \(label)", step: "DebugSimulationManager.triggerSoundProfileMock")
        
        // 1. Grab your actual current location from your MicrophoneManager
        guard let myLoc = DependencyContainer.shared.microphoneManager.currentLocation else {
            return
        }
        let myLatitude = myLoc.coordinate.latitude
        let myLongitude = myLoc.coordinate.longitude
        let randomLatOffset = Double.random(in: -0.0003...0.0003)
        let randomLonOffset = Double.random(in: -0.0003...0.0003)
        let threatLat = myLatitude + randomLatOffset
        let threatLon = myLongitude + randomLonOffset
        
        // Create a generic, non-moving sound event
        let newEvent = SoundEvent(
            sessionID: UUID(),
            timestamp: Date(),
            threatLabel: label,  // "knock", "alarm", etc.
            confidence: 0.99,             // High confidence so it triggers
            bearing: 0.0,                 // No specific direction
            distance: 0.1,                // Very close
            energy: 0.8,                  // Loud
            dopplerRate: 0.0,             // Not moving
            isApproaching: false,         // Not moving
            latitude: threatLat,
            longitude: threatLon,
            isRevealed: true,
            songLabel: nil
        )
        
        DependencyContainer.shared.acousticCoordinator.addEvent(newEvent)
        DependencyContainer.shared.notificationManager.sendEmergencyAlert(for: label)
    }
}
