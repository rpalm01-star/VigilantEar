import Foundation
import UIKit

struct HardwareCalibration {
    
    // --- 1. THE UNIFIED HARDWARE PROFILE ---
    private struct DeviceProfile {
        let micDistance: Double
        let aspectRatio: CGFloat
    }
    
    // --- 2. SINGLE SOURCE OF TRUTH ---
    private static var currentProfile: DeviceProfile {
        let model = deviceIdentifier
        
        // NOTE: Apple's internal hardware identifiers are offset from marketing names.
        // "iPhone17,x" is exactly the correct internal code for the iPhone 16 family!
        switch model {
            
            // MARK: - iPhone 16 Family (Internal: iPhone17,x)
        case "iPhone17,1": return DeviceProfile(micDistance: 0.147, aspectRatio: 1179.0 / 2556.0) // iPhone 16
        case "iPhone17,2": return DeviceProfile(micDistance: 0.160, aspectRatio: 1290.0 / 2796.0) // iPhone 16 Plus
        case "iPhone17,3": return DeviceProfile(micDistance: 0.149, aspectRatio: 1179.0 / 2556.0) // iPhone 16 Pro
        case "iPhone17,4": return DeviceProfile(micDistance: 0.163, aspectRatio: 1290.0 / 2796.0) // iPhone 16 Pro Max
            
            // MARK: - iPhone 15 Family (Internal: iPhone15,x and iPhone16,x)
        case "iPhone15,4": return DeviceProfile(micDistance: 0.147, aspectRatio: 1179.0 / 2556.0) // iPhone 15
        case "iPhone15,5": return DeviceProfile(micDistance: 0.160, aspectRatio: 1290.0 / 2796.0) // iPhone 15 Plus
        case "iPhone16,1": return DeviceProfile(micDistance: 0.146, aspectRatio: 1179.0 / 2556.0) // iPhone 15 Pro
        case "iPhone16,2": return DeviceProfile(micDistance: 0.159, aspectRatio: 1290.0 / 2796.0) // iPhone 15 Pro Max
            
            // MARK: - Generic Fallbacks
        case let x where x.hasPrefix("iPad"):
            return DeviceProfile(micDistance: 0.250, aspectRatio: 3.0 / 4.0)
        case let x where x.contains("Pro Max") || x.contains("Plus"):
            return DeviceProfile(micDistance: 0.160, aspectRatio: 1290.0 / 2796.0)
        case let x where x.hasPrefix("iPhone"):
            return DeviceProfile(micDistance: 0.145, aspectRatio: 1179.0 / 2556.0)
        default:
            return DeviceProfile(micDistance: 0.150, aspectRatio: 9.0 / 19.5)
        }
    }
    
    // --- 3. THE PUBLIC ACCESSORS ---
    /// The physical distance between the top/front and bottom microphones in meters.
    static var micBaseline: Double {
        if AppGlobals.usbMicropohone {
            return 0.3048 // External USB Array Override (1 foot)
        }
        return currentProfile.micDistance
    }
    
    /// The physical width-to-height ratio of the device screen.
    static var displayAspectRatio: CGFloat {
        return currentProfile.aspectRatio
    }
    
    /// Extracts the internal machine identifier (e.g., "iPhone17,4")
    private static var deviceIdentifier: String {
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
