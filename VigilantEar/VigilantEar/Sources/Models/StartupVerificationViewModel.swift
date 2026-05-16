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
    case notDetermined
}

/// A single verification task shown in the startup checklist.
struct VerificationTask: Identifiable {
    let id = UUID()
    let type: VerificationType
    var status: VerificationStatus = .pending
    var failureReason: LocalizedStringResource? = nil
}

/// The different checks performed during app startup.
enum VerificationType: LocalizedStringResource {
    case locationAuthorization = "Location Authorization"
    case stereoAudio = "Stereo Microphone Array"
    case audioRouting = "Audio Routing (Built-in Mic)"
    case neuralEngine = "Neural Engine (CoreML)"
    case storage = "Storage Availability"
    case orientation = "Landscape Orientation"
}

/// ViewModel that runs all startup diagnostics **sequentially** and reports results to the UI.
@Observable
@MainActor
final class StartupVerificationViewModel {
    
    // MARK: - Public State (observed by SwiftUI)
    
    var steps: [VerificationTask] = []
    var isFinished = false
    
    var allPassed: Bool {
        steps.allSatisfy { $0.status == .passed }
    }
    
    // MARK: - Private State
    private let locationManager = CLLocationManager()
    
    // MARK: - Initialization
    init() {
        resetSteps()
    }
    
    // MARK: - Private Helpers
    private func resetSteps() {
        steps = [
            VerificationTask(type: .locationAuthorization),
            VerificationTask(type: .stereoAudio),
            VerificationTask(type: .audioRouting),
            VerificationTask(type: .neuralEngine),
            VerificationTask(type: .storage),
            VerificationTask(type: .orientation),
        ]
        isFinished = false
    }
    
    // MARK: - Dynamic Updates
    func updateOrientationStatus(isLandscape: Bool) {
        guard let index = steps.firstIndex(where: { $0.type == .orientation }) else { return }
        
        if isLandscape {
            steps[index].status = .passed
            steps[index].failureReason = nil
        } else {
            steps[index].status = .failed
            steps[index].failureReason = AppGlobals.flipToLandscape
        }
    }
    
    // MARK: - Public API
    func runDiagnostics() async {
        resetSteps()
        
        // Set all to running initially for visual feedback
        for i in steps.indices {
            steps[i].status = .running
        }
        
        for (index, step) in steps.enumerated() {
            let startTime = Date()
            
            let result: (status: VerificationStatus, reason: LocalizedStringResource?)
            
            switch step.type {
            case .locationAuthorization:
                result = await checkLocation()
            case .stereoAudio:
                result = await checkStereoAudio()
            case .audioRouting:
                result = await checkAudioRouting()
            case .neuralEngine:
                result = await checkNeuralEngine()
            case .storage:
                result = await checkStorage()
            case .orientation:
                result = checkOrientation()
            }
            
            // Minimum 0.25 seconds display time for the running spinner
            let elapsed = Date().timeIntervalSince(startTime)
            let minimumDisplayTime: TimeInterval = 0.25
            if elapsed < minimumDisplayTime {
                try? await Task.sleep(for: .seconds(minimumDisplayTime - elapsed))
            }
            
            steps[index].status = result.status
            steps[index].failureReason = result.reason
        }
        
        isFinished = true
    }
    
    // MARK: - Individual Verification Checks
    private func checkLocation() async -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        let status = locationManager.authorizationStatus
        
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            for _ in 0..<30 {
                if locationManager.authorizationStatus != .notDetermined { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        
        let finalStatus = locationManager.authorizationStatus
        let passed = finalStatus == .authorizedWhenInUse || finalStatus == .authorizedAlways
        return passed ? (.passed, nil) : (.failed, AppGlobals.locRequired)
    }
    
    private func checkStereoAudio() async -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .denied {
            return (.failed, AppGlobals.micDenied)
        }
        if permission == .undetermined {
            guard await AVAudioApplication.requestRecordPermission() else {
                return (.failed, AppGlobals.micDenied)
            }
        }
        return await DependencyContainer.shared.microphoneManager.verifyStereoCapability()
    }
    
    private func checkAudioRouting() async -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .denied {
            return (.failed, AppGlobals.micDenied)
        }
        if permission == .undetermined {
            guard await AVAudioApplication.requestRecordPermission() else {
                return (.failed, AppGlobals.micDenied)
            }
        }
        return await DependencyContainer.shared.microphoneManager.verifyAudioRouting()
    }
    
    private func checkOrientation() -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return (.failed, AppGlobals.unknownDeviceOrientation)
        }
        let isLandscape = scene.effectiveGeometry.interfaceOrientation.isLandscape
        return isLandscape ? (.passed, nil) : (.failed, AppGlobals.flipToLandscape)
    }
    
    private func checkNeuralEngine() async -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        let hasANE = MLComputeDevice.allComputeDevices.contains { if case .neuralEngine = $0 { return true }; return false }
        return hasANE ? (.passed, nil) : (.failed, AppGlobals.noNeuralEngine)
    }
    
    private func checkStorage() async -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (.failed, AppGlobals.storageRequiredButMissing)
        }
        
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage, capacity > 80 * 1024 * 1024 {
                return (.passed, nil)
            } else {
                return (.failed, AppGlobals.insufficientStorage)
            }
        } catch {
            return (.failed, AppGlobals.storageCheckFailed)
        }
    }
}
