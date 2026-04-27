//  AppGlobals.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/19/26.
//

import Synchronization
import SwiftUI

nonisolated struct AppGlobals {
    
    // MARK: - Theming & Config (your existing code)
    private static let _lightGray = Mutex<Color>(Color(white: 0.62))
    public static var lightGray: Color {
        get { _lightGray.withLock { $0 } }
    }
    
    private static let _darkGray = Mutex<Color>(Color(white: 0.35))
    public static var darkGray: Color {
        get { _darkGray.withLock { $0 } }
    }
    
    private static let _darkerGray = Mutex<Color>(Color(white: 0.25))
    public static var darkerGray: Color {
        get { _darkerGray.withLock { $0 } }
    }
    
    private static let _darkerGrayWithOpacity = Mutex<Color>(Color(white: 0.25, opacity: 0.9))
    public static var darkerGrayWithOpacity: Color {
        get { _darkerGrayWithOpacity.withLock { $0 } }
    }
    
    private static let _appVersion = Mutex<String>(" 1.0.0")
    public static var appVersion: String {
        get { _appVersion.withLock { $0 } }
    }
    
    private static let _dataStoreName = Mutex<String>("threats")
    public static var dataStoreName: String {
        get { _dataStoreName.withLock { $0 } }
    }
    
    private static let _simluatedFiretruckLabel = Mutex<String>("simulated_firetruck")
    public static var simluatedFiretruckLabel: String {
        get { _simluatedFiretruckLabel.withLock { $0 } }
    }
    
    private static let _logDataStoreName = Mutex<String>("logs")
    public static var logDataStoreName: String {
        get { _logDataStoreName.withLock { $0 } }
    }
    
    private static let _exceptionDataStoreName = Mutex<String>("exceptions")
    public static var exceptionsDataStoreName: String {
        get { _exceptionDataStoreName.withLock { $0 } }
    }

    private static let _simFireLabel = Mutex<String>("simulated_fire_truck")
    public static var simulatedFireTruck: String {
        get { _simFireLabel.withLock { $0 } }
    }
    
    private static let _logToCloud = Mutex<Bool>(false)
    public static var logToCloud: Bool {
        get { _logToCloud.withLock { $0 } }
        set { _logToCloud.withLock { $0 = newValue } }
    }
    
    private static let _purgeCloudLogsOnStartup = Mutex<Bool>(true)
    public static var purgeCloudLogsOnStartup: Bool {
        get { _purgeCloudLogsOnStartup.withLock { $0 } }
        set { _purgeCloudLogsOnStartup.withLock { $0 = newValue } }
    }
    
    private static let _usbMicropohone = Mutex<Bool>(false)
    public static var usbMicropohone: Bool {
        get { _usbMicropohone.withLock { $0 } }
    }
    
    public static let filteredCategories: Set<String> = [
        ThreatCategory.ignored.rawValue
    ]
    
    // MARK: - Global Logging (new)
    /// Fire-and-forget log that can be called from **any** context safely.
    nonisolated static func doLog(message: String, step: String = "APP", logName: String = AppGlobals.logDataStoreName, isError: Bool = false) {
        Task.detached(priority: .background) {
            print(message)
            await PerformanceLogger.shared.logTelemetry(step: step, message: message, logName: logName, isError: isError)
        }
    }

    
    
    // MARK: - Location & Heading Power Tuning
    //
    // These four values control the balance between battery life and how "alive" the app feels.
    // Tweak them while testing on your iPhone and watch the Energy Impact numbers + turning feel.
    //
    // === LOCATION (GPS) ===
    // locationUpdateThrottle: How often (in seconds) we allow a new GPS position to be sent to the pipeline.
    //   - Lower value (0.3–0.5) = more responsive map dot, but higher battery drain
    //   - Higher value (1.0–2.0) = smoother battery, but the blue dot on the map updates less often
    //   Recommended range: 0.6 – 1.2 seconds
    static let locationUpdateThrottle: TimeInterval = 0.5
    
    // locationDistanceFilter: iOS will only deliver a new location update after you've moved this many meters.
    //   - Lower value (3–5) = more frequent updates, feels more "live"
    //   - Higher value (10–15) = fewer updates, saves significant power
    //   Recommended range: 5 – 12 meters
    static let locationDistanceFilter: Double = 8.0
    
    // === HEADING (COMPASS) ===
    // headingUpdateThrottle: How often (in seconds) we allow a new heading value to be sent to the pipeline.
    //   - This is the one that affects "turning the phone" feel the most.
    //   - Lower value (0.1–0.15) = buttery smooth turning, slightly higher power
    //   - Higher value (0.25–0.4) = noticeable lag when rotating, better battery
    //   Recommended range: 0.12 – 0.25 seconds (0.18 feels great for most people)
    static let headingUpdateThrottle: TimeInterval = 0.20
    
    // headingFilterDegrees: iOS will only deliver a new heading update when the device has rotated at least this many degrees.
    //   - Lower value (1–2) = very sensitive, almost no filtering, can feel jittery
    //   - Higher value (5–8) = smoother but can feel "steppy" when turning slowly
    //   Recommended range: 2.5 – 4.5 degrees
    static let headingFilterDegrees: Double = 3.5
    
    // MARK: - Machine Learning Thresholds
    enum ML {
        /// Absolute floor for the observer to even bother looking at a result
        static let absoluteMinimumConfidence: Double = 0.20
        
        /// The confidence required to trigger a background Shazam match
        static let shazamTriggerThreshold: Double = 0.65
        
        /// The pipeline floor for music to prevent it from dropping off during quiet parts
        static let musicConfidenceFloor: Double = 0.50
        
        /// Confidence needed to treat a muffled emergency sound as a standard vehicle
        static let emergencyDowngradeThreshold: Double = 0.70
    }
    
    // MARK: - Acoustic Physics & Radar
    enum Physics {
        /// The minimum volume peak required to track a standard sound
        static let minimumAmbientPeak: Float = 0.04
        
        /// The minimum volume peak required to track a vehicle (lower because of low frequencies)
        static let minimumVehiclePeak: Float = 0.015
        
        /// How many degrees of bearing difference before we consider it a separate physical object
        static let ambientBearingTolerance: Double = 45.0
        static let vehicleBearingTolerance: Double = 10.0
    }
    
    // MARK: - Timing & Debounce (Seconds)
    enum Timing {
        /// How long an old threat stays in the pipeline memory before being purged
        static let threatMemoryLifespan: TimeInterval = 4.0
        
        /// How long an event is allowed to live on the SwiftUI HUD
        static let hudEventLifespan: TimeInterval = 10.0
        
        /// The strict pipeline debounce to prevent sub-second FFT cloning
        static let pipelineDebounce: TimeInterval = 0.85
        
        /// How long to pause Shazam accumulation after a successful match
        static let shazamCooldown: TimeInterval = 180.0
    }
}
