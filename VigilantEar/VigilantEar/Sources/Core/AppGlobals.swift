//
//  AppGlobals.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/19/26.
//

import Synchronization

nonisolated struct AppGlobals {
    
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
    
    private static let _logToCloud = Mutex<Bool>(false)   // initial value
    public static var logToCloud: Bool {
        get {
            _logToCloud.withLock { $0 }      // safe read
        }
    }

    private static let _usbMicropohone = Mutex<Bool>(false)   // initial value
    public static var usbMicropohone: Bool {
        get {
            _usbMicropohone.withLock { $0 }      // safe read
        }
    }
    
}
