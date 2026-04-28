import Foundation
import Observation
import CoreML
import UserNotifications
import AVFAudio
import AVFoundation
import UIKit
import CoreLocation

enum VerificationStatus {
    case pending, running, passed, failed
}

struct VerificationTask: Identifiable {
    let id = UUID()
    let type: VerificationType
    var status: VerificationStatus = .pending
    var failureReason: String? = nil
}

enum VerificationType: String {
    case stereoAudio = "Stereo Microphone Array"
    case audioRouting = "Audio Routing (Built-in Mic)"
    case orientation = "Landscape Orientation"
    case locationAccess = "GPS Tactical Mapping"
    case neuralEngine = "Neural Engine (CoreML)"
    case storage = "Storage Access"
    case notifications = "Emergency Push Alerts" // 🚨 NEW: Verify our lock-screen bypass!
}

@Observable
@MainActor
final class StartupVerificationViewModel {
    
    var steps: [VerificationTask] = []
    
    var isFinished = false
    var allPassed: Bool { steps.allSatisfy { $0.status == .passed } }
    
    private let locationManager = CLLocationManager()
    
    init() {
        resetSteps()
    }
    
    private func resetSteps() {
        steps = [
            VerificationTask(type: .stereoAudio),
            VerificationTask(type: .audioRouting),
            VerificationTask(type: .orientation),
            VerificationTask(type: .locationAccess),
            VerificationTask(type: .neuralEngine),
            VerificationTask(type: .storage),
            VerificationTask(type: .notifications) // 🚨 Added to UI checklist
        ]
        isFinished = false
    }
    
    func runDiagnostics() async {
        resetSteps()
        for i in steps.indices { steps[i].status = .running }
        
        async let stereoResult = checkStereoAudio()
        async let routingResult = checkAudioRouting()
        let orientationResult = checkOrientation()
        async let locationResult = checkLocation()
        async let neuralResult = checkNeuralEngine()
        async let storageResult = checkStorage()
        async let notificationResult = checkNotifications() // 🚨 Fire the new check
        
        let results = await [stereoResult, routingResult, orientationResult, locationResult, neuralResult, storageResult, notificationResult]
        
        for (index, result) in results.enumerated() {
            steps[index].status = result.status
            steps[index].failureReason = result.reason
        }
        
        isFinished = true
    }
    
    private func checkLocation() async -> (status: VerificationStatus, reason: String?) {
        let status = locationManager.authorizationStatus
        
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            
            for _ in 0..<30 {
                if locationManager.authorizationStatus != .notDetermined { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        
        let finalStatus = locationManager.authorizationStatus
        if finalStatus == .authorizedWhenInUse || finalStatus == .authorizedAlways {
            return (.passed, nil)
        } else {
            return (.failed, "Location required to map acoustic events.")
        }
    }
    
    // MARK: - Stereo Acoustic Checks
    
    private func checkStereoAudio() async -> (status: VerificationStatus, reason: String?) {
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .denied { return (.failed, "Microphone permission denied") }
        if permission == .undetermined {
            guard await AVAudioApplication.requestRecordPermission() else {
                return (.failed, "Microphone permission denied")
            }
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .mixWithOthers])
            
            // 🚨 THE HAPTICS FIX: Ensure diagnostic tests don't kill the Taptic Engine!
            try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
            
            try audioSession.setActive(true)
        } catch {
            return (.failed, "Audio Session locked")
        }
        
        guard let builtInMic = audioSession.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            return (.failed, "No built-in mic detected")
        }
        
        let hasStereo = builtInMic.dataSources?.contains { source in
            source.supportedPolarPatterns?.contains(.stereo) == true
        } ?? false
        
        if hasStereo {
            return (.passed, nil)
        } else {
            return (.failed, "Device lacks Stereo Array support")
        }
    }
    
    private func checkAudioRouting() async -> (status: VerificationStatus, reason: String?) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 🚨 THE HAPTICS FIX: Updated to match main app session to prevent lockouts
            try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP, .mixWithOthers])
            try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try audioSession.setActive(true)
            
            let currentRoute = audioSession.currentRoute
            if currentRoute.inputs.contains(where: { $0.portType == .bluetoothHFP || $0.portType == .headsetMic || $0.portType == .carAudio }) {
                return (.failed, "Disconnect external microphones")
            }
            return (.passed, nil)
        } catch {
            return (.failed, "Audio routing failed")
        }
    }
    
    private func checkOrientation() -> (status: VerificationStatus, reason: String?) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return (.failed, "Cannot determine orientation")
        }
        
        if scene.effectiveGeometry.interfaceOrientation.isLandscape {
            return (.passed, nil)
        } else {
            return (.failed, "Rotate phone to Landscape")
        }
    }
    
    private func checkNeuralEngine() async -> (status: VerificationStatus, reason: String?) {
        let hasANE = MLComputeDevice.allComputeDevices.contains { if case .neuralEngine = $0 { return true }; return false }
        return hasANE ? (.passed, nil) : (.failed, "Neural Engine missing")
    }
    
    private func checkStorage() async -> (status: VerificationStatus, reason: String?) {
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return (.failed, "No access") }
        
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage, capacity > 80 * 1024 * 1024 {
                return (.passed, nil)
            } else {
                return (.failed, "Low storage (~80MB req)")
            }
        } catch {
            return (.failed, "Storage test failed")
        }
    }
    
    // MARK: - NEW: Notification Gate
    private func checkNotifications() async -> (status: VerificationStatus, reason: String?) {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return (.passed, nil)
        case .denied:
            return (.failed, "Push access denied in Settings")
        case .notDetermined:
            // Fallback: If it somehow hasn't been requested yet, request it right here to pass the diagnostic
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                return granted ? (.passed, nil) : (.failed, "Permission required for alerts")
            } catch {
                return (.failed, "Notification test failed")
            }
        @unknown default:
            return (.failed, "Unknown status")
        }
    }
}
