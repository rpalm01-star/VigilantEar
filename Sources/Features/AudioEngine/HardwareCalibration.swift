import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct HardwareCalibration {
    /// Returns the physical distance (in meters) between the primary mic array
    static var micBaseline: Double {
        #if targetEnvironment(simulator) || os(macOS)
        // M4 MacBook Air "Studio Quality" 3-mic array spacing
        return 0.20 // ~20cm across the top/side chassis
        #else
        // iPhone Standard 3-mic array spacing (Bottom to Top-earpiece)
        return 0.12 // ~12cm vertical distance
        #endif
    }
    
    /// Returns the device-specific identifier for research logging
    static var deviceModel: String {
        return UIDevice.current.modelName
    }
}

// Extension to get human-readable model names (e.g., "iPhone 15 Pro")
extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
