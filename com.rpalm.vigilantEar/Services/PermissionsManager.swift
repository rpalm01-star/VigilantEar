import Foundation
import AVFoundation
import CoreLocation

@Observable
class PermissionsManager {
    var isMicrophoneAuthorized = false
    var isLocationAuthorized = false
    
    /// Requests all necessary hardware access for VigilantEar
    func requestAllPermissions() async {
        await requestMicrophoneAccess()
        requestLocationAccess()
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
}
