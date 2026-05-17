//  AppGlobals.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/19/26.
//

import Synchronization
import SwiftUI
import OSLog
import Foundation
import CoreLocation

nonisolated struct AppGlobals {
    
    // MARK: - Localizable Strings
    public static let alarms                        : LocalizedStringResource = "Alarms"
    public static let alertPreferences              : LocalizedStringResource = "Alert Preferences"
    public static let allRightsReserved             : LocalizedStringResource = "All rights reserved."
    public static let appPreferencesHeader          : LocalizedStringResource = "App Preferences"
    public static let appTitle                      : LocalizedStringResource = "VIGILANT EAR"
    public static let audioRouting                  : LocalizedStringResource = "Audio Routing (Built-in Mic)"
    public static let unknownDeviceOrientation      : LocalizedStringResource = "Cannot determine device orientation"
    public static let customizations                : LocalizedStringResource = "Customizations"
    public static let detected                      : LocalizedStringResource = "Detected"
    public static let disconnectExternaMic          : LocalizedStringResource = "Disconnect external mic"
    public static let done                          : LocalizedStringResource = "Done"
    public static let doorbells                     : LocalizedStringResource = "Doorbells"
    public static let emergencyAlertLabel           : LocalizedStringResource = "EMERGENCY ALERT"
    public static let emergencyAlertsSimulator      : LocalizedStringResource = "Emergency Alerts Simulator"
    public static let emergencyAlertText            : LocalizedStringResource = "App Emergency Alerts are enabled."
    public static let fakeCAPAlertText              : LocalizedStringResource = "(SIM) Coffee Deficiency Alert"
    public static let firetruckSimulator            : LocalizedStringResource = "Firetruck Simulator"
    public static let flipToLandscape               : LocalizedStringResource = "Flip to Landscape mode"
    public static let insufficientStorage           : LocalizedStringResource = "Insufficient storage"
    public static let legalHeader                   : LocalizedStringResource = "Legal"
    public static let listening                     : LocalizedStringResource = "LISTENING..."
    public static let loading                       : LocalizedStringResource = "Loading"
    public static let locRequired                   : LocalizedStringResource = "Location access denied"
    public static let micDenied                     : LocalizedStringResource = "Microphone permission denied"
    public static let micNotFound                   : LocalizedStringResource = "Mic not found"
    public static let neuralEngine                  : LocalizedStringResource = "Neural Engine (CoreML)"
    public static let noNeuralEngine                : LocalizedStringResource = "ANE neural engine missing"
    public static let notifications                 : LocalizedStringResource = "Emergency Push Alerts"
    public static let notificationsDisabled         : LocalizedStringResource = "Notifications disabled in Settings"
    public static let notificationPermissionRequired: LocalizedStringResource = "Notification permission required"
    public static let notificationStatusUnknown     : LocalizedStringResource = "Notification status unknown"
    public static let offline                       : LocalizedStringResource = "OFFLINE"
    public static let orientation                   : LocalizedStringResource = "Landscape Orientation"
    public static let peopleCloseby                 : LocalizedStringResource = "People Closeby"
    public static let privacyPolicy                 : LocalizedStringResource = "Privacy Policy"
    public static let retrySystemChecks             : LocalizedStringResource = "RETRY SYSTEM CHECKS"
    public static let severeWeather                 : LocalizedStringResource = "Severe Weather"
    public static let simulatorsHeader              : LocalizedStringResource = "Simulators"
    public static let sirens                        : LocalizedStringResource = "Sirens"
    public static let spatialArrayMisaligned        : LocalizedStringResource = "SPATIAL ARRAY MISALIGNED"
    public static let stereoMicrophoneArray         : LocalizedStringResource = "Stereo Microphone Array"
    public static let stereoUnsupported             : LocalizedStringResource = "Stereo not supported"
    public static let storage                       : LocalizedStringResource = "Storage Availability"
    public static let storageCheckFailed            : LocalizedStringResource = "Storage check failed"
    public static let storageRequiredButMissing     : LocalizedStringResource = "Storage required but missing"
    public static let support                       : LocalizedStringResource = "Support"
    public static let appInfoReadMe                 : LocalizedStringResource = "App Info"
    public static let synchronizationFailed         : LocalizedStringResource = "Synchronization failed"
    public static let systemInitialization          : LocalizedStringResource = "SYSTEM INITIALIZATION"
    public static let systemsAreAGo                 : LocalizedStringResource = "SYSTEMS ARE A GO!"
    public static let openSystemSettingsForApp      : LocalizedStringResource = "Click for App System Settings"
    public static let telemetryLabel                : LocalizedStringResource = "Telemetry"
    public static let termsOfService                : LocalizedStringResource = "Terms of Service"
    public static let turnToLandscape               : LocalizedStringResource = "(Turn to landscape mode)"
    public static let verifyingSubsystems           : LocalizedStringResource = "Verifying subsystems..."
    public static let locationAccessRequired        : LocalizedStringResource = "GPS Location"
    public static let wingdingsInc                  : LocalizedStringResource = "© 2026 Wingdings, Inc."
    public static let ONLINE                        : LocalizedStringResource = "ONLINE"
    public static let OFFLINE                       : LocalizedStringResource = "OFFLINE"
    
    // Do not localize
    public static let appEmail = "vigilantear@wingdingssocial.com"
    public static let localPersistenceIdentifier = "VigilantEar_PersistedAlerts"
    public static let vigilantEarKeystoreIdentifier = "VigilandEarUUID"
    public static let dataStoreName = "threats"
    public static let installationsDataStoreName = "installations"
    public static let logDataStoreName = "logs"
    public static let exceptionsDataStoreName = "exceptions"
    public static let simulatedFireTruck = "simulated_fire_truck"
    public static let waveform = "waveform"
    public static let usbMicropohone = false
    public static let appLabel : String = "APP"
    public static let meteoGateKey = "d187be71400ecd90df5e396f44c75f03a8f2281fc116d15f52830a702149133b"
    
    // This is just a default value until the application sets it during initialization.
    public static let version : String = "unset"
    public static let sessionID = UUID()
    public static let defaultCameraDistance : Double = 400.0
    
    // MARK: - Theming & Config (Cleaned up read-only constants)
    public static let lightGray = Color(white: 0.62)
    public static let darkGray = Color(white: 0.35)
    public static let darkerGray = Color(white: 0.25)
    public static let darkerGrayWithOpacity = Color(white: 0.25, opacity: 0.9)
    
    // MARK: - Map & Camera
    static let emergencyCircleRadiusMeters: CLLocationDistance = 304.8   // 1000 ft
    static let warningCircleRadiusMeters: CLLocationDistance = 152.4    // 500 ft
    static let safeCircleRadiusMeters: CLLocationDistance = 9.144       // 30 ft
    
    // MARK: - User Annotation
    static let userArrowFontSize: CGFloat = 24
    static let userDotSize: CGFloat = 14
    static let userArrowYOffset: CGFloat = -12
    
    // MARK: - Route & Overlays
    static let simulatedRouteOpacity: Double = 0.2
    static let routeLineWidth: CGFloat = 3
    
    // MARK: - Emergency Ring
    static let pulsingRingSize: CGFloat = 250
    static let pulsingAnimationDuration: Double = 1.4
    
    // MARK: - ThreatMarker
    static let threatIconFontSize: CGFloat = 18
    static let emergencyIconFontSize: CGFloat = 24
    static let threatIconPadding: CGFloat = 8
    static let threatRimOpacityNormal: Double = 0.25
    static let threatRimOpacityEmergency: Double = 0.50
    static let threatRimWidthNormal: CGFloat = 1
    static let threatRimWidthEmergency: CGFloat = 2
    
    // MARK: - Sidebar (the 1.0275 was a tiny hack to prevent clipping)
    static let sidebarWidthMultiplier: Double = 0.50
    static let sidebarContainerMultiplier: Double = 1.0275   // keeps the panel from cutting off on some devices
    
    // MARK: - Animations
    static let cameraAnimationDuration: Double = 1.5
    static let menuSlideDuration: Double = 0.35
    static let menuDamping: Double = 0.8
    
    public static let filteredCategories: Set<String> = [
        ThreatCategory.ignored.rawValue
    ]
    
    private static let _appVersion = Mutex<String>(version)
    public static var appVersion: String {
        get { _appVersion.withLock { $0 } }
        set { _appVersion.withLock { $0 = newValue } }
    }
    
    private static let _logToCloud = Mutex<Bool>(false)
    public static var logToCloud: Bool {
        get { _logToCloud.withLock { $0 } }
        set { _logToCloud.withLock { $0 = newValue } }
    }
    
    private static let permanentKeystoreID = "54F07C12-6125-4492-A064-C000A0557216"
    
    private static let _currentDeviceID = Mutex<String>("unset")
    public static var currentDeviceID: String {
        get { _currentDeviceID.withLock { $0 } }
        set {
            _currentDeviceID.withLock { $0 = newValue }
            // Small optimization: check newValue directly instead of re-getting
            if (newValue == permanentKeystoreID) {
                isDebugDevice = true
            } else {
                isDebugDevice = false
            }
        }
    }
    
    private static let _isDebugDevice = Mutex<Bool>(false)
    public static var isDebugDevice: Bool {
        get { _isDebugDevice.withLock { $0 } }
        set { _isDebugDevice.withLock { $0 = newValue } }
    }
    
    private static let _purgeCloudLogsOnStartup = Mutex<Bool>(false)
    public static var purgeCloudLogsOnStartup: Bool {
        get { _purgeCloudLogsOnStartup.withLock { $0 } }
        set { _purgeCloudLogsOnStartup.withLock { $0 = newValue } }
    }
    
    // MARK: - Global Logging
    /// Fire-and-forget log that can be called from **any** context safely.
    nonisolated static func doLog(message: String, step: String = appLabel, isError: Bool = false) {
        Task { @MainActor in
            CloudKitLogManager.log(step: step, message: message, isError: isError)
        }
    }
    
    // MARK: - Location & Heading Power Tuning
    static let locationUpdateThrottle: TimeInterval = 1.2
    static let locationDistanceFilter: Double = 15.0
    static let headingUpdateThrottle: TimeInterval = 0.5
    static let headingFilterDegrees: Double = 10.0
    
    // MARK: - Machine Learning Thresholds
    enum ML {
        static let absoluteMinimumConfidence: Double = 0.05
        static let shazamTriggerThreshold: Double = 0.60
    }
    
    // MARK: - Acoustic Physics & Radar
    enum Physics {
        static let minimumAmbientPeak: Float = 0.05
        static let minimumVehiclePeak: Float = 0.025
        static let ambientBearingTolerance: Double = 25.0
        static let vehicleBearingTolerance: Double = 5.0
    }
    
    // MARK: - Timing & Debounce (Seconds)
    enum Timing {
        static let threatMemoryLifespan: TimeInterval = 5.0
        static let hudEventLifespan: TimeInterval = 15.0
        static let pipelineDebounce: TimeInterval = 0.85
        static let shazamCooldown: TimeInterval = 120.0
    }
    
    // MARK: - Target Tracking (Dead Reckoning & Smoothing)
    enum Tracking {
        static let smoothingFactor: Double = 0.85
        static let distanceSmoothingFactor: Double = 0.7
        static let maxEstimatedSpeedMPS: Double = 35.0
    }
    
    // MARK: - Geolocation Helpers
    enum Geo {
        static let earthRadiusMeters: Double = 6378137.0
    }
    
    // MARK: - Rendering
    enum Rendering {
        // Map / rendering
        static let defaultMapZoom = 0.005
        static let targetGlideInterval: TimeInterval = 0.1          // was 0.033 → 10 Hz
        static let targetGlideDistanceMultiplier: Double = 0.1
        static let overlayUpdateDebounce: TimeInterval = 0.2
        
        // Colors (already have neon ones — centralize)
        static let neonGreen = Color(red: 0.0, green: 1.0, blue: 0.4)
        static let neonCyan  = Color(red: 0.0, green: 0.9, blue: 1.0)
    }
    
    /// Neural Ticker HUD configuration
    enum NeuralTicker {
        static let minimumConfidence: Double = 0.20
        static let ttl: TimeInterval = 15.0
        static let cooldown: TimeInterval = 12.0
        static let topOffset: CGFloat = 65
        static let heightMultiplier: CGFloat = 0.9
        static let fontSize: CGFloat = 11
        static let textOpacity: Double = 0.82
        static let insertResponse: Double = 0.42
        static let insertDamping: Double = 0.78
        static let fadeOutDuration: Double = 0.5
    }
    
    // MARK: - Multi-Vehicle Icon Tint
    enum VehicleColors {
        static let palette: [Color] = [
            .blue,
            .teal,
            .cyan,
            .indigo,
            .mint,
            .blue.opacity(0.9),
        ]
        
        static func iconTint(for sessionID: UUID) -> Color {
            let hash = abs(sessionID.hashValue) % palette.count
            return palette[hash]
        }
    }
    
    public static func localizeText(label: String) -> String {
        let langCode = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "en"
        var a : LocalizedStringResource = LocalizedStringResource(String.LocalizationValue(label.lowercased()))
        a.locale = Locale(identifier: langCode)
        return String(localized: a)
    }

}
