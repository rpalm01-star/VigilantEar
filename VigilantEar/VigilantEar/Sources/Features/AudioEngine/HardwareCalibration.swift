import Foundation
import UIKit

struct HardwareCalibration {
    
    /// The physical distance between the top/front and bottom microphones in meters.
    static var micBaseline: Double {
        let model = deviceIdentifier
        
        // These are approximations based on chassis height.
        // You can fine-tune these if you notice slight bearing drifts on specific devices.
        switch model {
            
            // MARK: - iPhone 16 Family
        case "iPhone17,1": return 0.147 // iPhone 16
        case "iPhone17,2": return 0.160 // iPhone 16 Plus
        case "iPhone17,3": return 0.149 // iPhone 16 Pro
        case "iPhone17,4": return 0.163 // iPhone 16 Pro Max (Your device)
            
            // MARK: - iPhone 15 Family
        case "iPhone15,4": return 0.147 // iPhone 15
        case "iPhone15,5": return 0.160 // iPhone 15 Plus
        case "iPhone16,1": return 0.146 // iPhone 15 Pro
        case "iPhone16,2": return 0.159 // iPhone 15 Pro Max
            
            // MARK: - Older / Generic Fallbacks
        case let x where x.hasPrefix("iPad"):
            return 0.250 // iPads have completely different mic arrays
        case let x where x.contains("Pro Max") || x.contains("Plus"):
            return 0.160 // Generic large iPhone
        case let x where x.hasPrefix("iPhone"):
            return 0.145 // Generic standard iPhone
        default:
            return 0.150 // Safe middle ground
        }
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
