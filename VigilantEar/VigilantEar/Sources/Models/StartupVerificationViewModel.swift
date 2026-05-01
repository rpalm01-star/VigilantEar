import Foundation
import Observation
import CoreML
import UserNotifications
import AVFAudio
import AVFoundation
import UIKit
import CoreLocation

/// Represents the current state of a single verification check.
enum VerificationStatus {
    case pending
    case running
    case passed
    case failed
}

/// A single verification task shown in the startup checklist.
struct VerificationTask: Identifiable {
    let id = UUID()
    let type: VerificationType
    var status: VerificationStatus = .pending
    var failureReason: String? = nil
}

/// The different checks performed during app startup.
enum VerificationType: String {
    case stereoAudio = "Stereo Microphone Array"
    case audioRouting = "Audio Routing (Built-in Mic)"
    case orientation = "Landscape Orientation"
    case locationAccess = "GPS Tactical Mapping"
    case neuralEngine = "Neural Engine (CoreML)"
    case storage = "Storage Availability"
    case notifications = "Emergency Push Alerts"
}

/// ViewModel that runs all startup diagnostics in parallel and reports results to the UI.
///
/// This class is responsible for:
/// - Verifying hardware capabilities (stereo mics, Neural Engine, etc.)
/// - Checking permissions (Location, Microphone, Notifications)
/// - Ensuring the device is in the correct state (Landscape, sufficient storage)
@Observable
@MainActor
final class StartupVerificationViewModel {
    
    // MARK: - Public State (observed by SwiftUI)
    
    /// List of verification steps shown in the startup checklist.
    var steps: [VerificationTask] = []
    
    /// Whether the full diagnostic run has completed.
    var isFinished = false
    
    /// Convenience computed property: true only if **every** step passed.
    var allPassed: Bool {
        steps.allSatisfy { $0.status == .passed }
    }
    
    
    // MARK: - Private State
    
    private let locationManager = CLLocationManager()
    
    
    // MARK: - Initialization
    
    init() {
        resetSteps()
    }
    
    
    // MARK: - Public API
    
    /// Resets all steps to pending and runs the full diagnostic suite in parallel.
    func runDiagnostics() async {
        resetSteps()
        
        // Mark everything as running for better UX feedback
        for i in steps.indices { steps[i].status = .running }
        
        // Run independent checks in parallel
        async let stereoResult     = checkStereoAudio()
        async let routingResult    = checkAudioRouting()
        let orientationResult      = checkOrientation()
        async let locationResult   = checkLocation()
        async let neuralResult     = checkNeuralEngine()
        async let storageResult    = checkStorage()
        async let notificationResult = checkNotifications()
        
        // Wait for all results
        let results = await [stereoResult, routingResult, orientationResult, locationResult, neuralResult, storageResult, notificationResult]
        
        // Apply results back to the UI
        for (index, result) in results.enumerated() {
            steps[index].status = result.status
            steps[index].failureReason = result.reason
        }
        
        isFinished = true
    }
    
    
    // MARK: - Individual Verification Checks
    
    private func checkLocation() async -> (status: VerificationStatus, reason: String?) {
        let status = locationManager.authorizationStatus
        
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            
            // Poll for up to 15 seconds
            for _ in 0..<30 {
                if locationManager.authorizationStatus != .notDetermined { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        
        let finalStatus = locationManager.authorizationStatus
        if finalStatus == .authorizedWhenInUse || finalStatus == .authorizedAlways {
            return (.passed, nil)
        } else {
            return (.failed, "Location permission required for tactical mapping.")
        }
    }
    
    private func checkStereoAudio() async -> (status: VerificationStatus, reason: String?) {
        let permission = AVAudioApplication.shared.recordPermission
        
        if permission == .denied {
            return (.failed, "Microphone permission denied")
        }
        
        if permission == .undetermined {
            guard await AVAudioApplication.requestRecordPermission() else {
                return (.failed, "Microphone permission denied")
            }
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
            try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try audioSession.setActive(true)
        } catch {
            return (.failed, "Failed to configure audio session")
        }
        
        guard let builtInMic = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            return (.failed, "No built-in microphone detected")
        }
        
        let hasStereo = builtInMic.dataSources?.contains { source in
            source.supportedPolarPatterns?.contains(.stereo) == true
        } ?? false
        
        return hasStereo ? (.passed, nil) : (.failed, "Device does not support stereo microphone array")
    }
    
    private func checkAudioRouting() async -> (status: VerificationStatus, reason: String?) {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP, .mixWithOthers])
            try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try audioSession.setActive(true)
            
            let currentRoute = audioSession.currentRoute
            if currentRoute.inputs.contains(where: { $0.portType == .bluetoothHFP || $0.portType == .headsetMic || $0.portType == .carAudio }) {
                return (.failed, "Please disconnect external microphones")
            }
            return (.passed, nil)
        } catch {
            return (.failed, "Audio routing configuration failed")
        }
    }
    
    private func checkOrientation() -> (status: VerificationStatus, reason: String?) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return (.failed, "Unable to determine device orientation")
        }
        
        if scene.effectiveGeometry.interfaceOrientation.isLandscape {
            return (.passed, nil)
        } else {
            return (.failed, "Please rotate device to Landscape mode")
        }
    }
    
    private func checkNeuralEngine() async -> (status: VerificationStatus, reason: String?) {
        let hasANE = MLComputeDevice.allComputeDevices.contains { if case .neuralEngine = $0 { return true }; return false }
        return hasANE ? (.passed, nil) : (.failed, "Neural Engine (ANE) not available on this device")
    }
    
    private func checkStorage() async -> (status: VerificationStatus, reason: String?) {
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (.failed, "Unable to access storage")
        }
        
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage, capacity > 80 * 1024 * 1024 {
                return (.passed, nil)
            } else {
                return (.failed, "Insufficient storage (minimum 80 MB required)")
            }
        } catch {
            return (.failed, "Storage check failed")
        }
    }
    
    private func checkNotifications() async -> (status: VerificationStatus, reason: String?) {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return (.passed, nil)
        case .denied:
            return (.failed, "Notifications are disabled in Settings")
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                return granted ? (.passed, nil) : (.failed, "Notification permission required")
            } catch {
                return (.failed, "Failed to request notification permission")
            }
        @unknown default:
            return (.failed, "Unknown notification status")
        }
    }
    
    
    // MARK: - Private Helpers
    
    private func resetSteps() {
        steps = [
            VerificationTask(type: .stereoAudio),
            VerificationTask(type: .audioRouting),
            VerificationTask(type: .orientation),
            VerificationTask(type: .locationAccess),
            VerificationTask(type: .neuralEngine),
            VerificationTask(type: .storage),
            VerificationTask(type: .notifications)
        ]
        isFinished = false
    }
}
