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
    
    private static let _logToCloud = Mutex<Bool>(false)
    public static var logToCloud: Bool {
        get { _logToCloud.withLock { $0 } }
        set { _logToCloud.withLock { $0 = newValue } }
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
    nonisolated static func doLog(message: String, step: String = "APP") {
        Task.detached(priority: .background) {
            print(message)
            await PerformanceLogger.shared.logTelemetry(step: step, message: message)
        }
    }
}
