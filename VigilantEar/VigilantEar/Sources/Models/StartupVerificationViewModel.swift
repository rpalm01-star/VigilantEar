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
    
    // 👇 The new flag to determine if the "Open Settings" text should be appended
    var isPermissionRelated: Bool = false
}

/// The different checks performed during app startup.
enum VerificationType: LocalizedStringResource {
    case locationAuthorization = "Location Authorization"
    case stereoAudio = "Stereo Microphone Array"
    case audioRouting = "Microphone Authorization"
    case neuralEngine = "Neural Engine (CoreML)"
    case storage = "Storage Availability"
    case orientation = "Landscape Orientation"
}

/// ViewModel that runs all startup diagnostics **concurrently** and reports results to the UI.
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
            // 👇 Flagging the iOS permission checks as true
            VerificationTask(type: .locationAuthorization, isPermissionRelated: true),
            VerificationTask(type: .audioRouting, isPermissionRelated: true),
            // 👇 Hardware and environment checks remain false
            //VerificationTask(type: .stereoAudio, isPermissionRelated: false),
            VerificationTask(type: .neuralEngine, isPermissionRelated: false),
            VerificationTask(type: .storage, isPermissionRelated: false),
            VerificationTask(type: .orientation, isPermissionRelated: false),
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
        
        // Create a TaskGroup to run all verification steps concurrently
        await withTaskGroup(of: (Int, VerificationStatus, LocalizedStringResource?).self) { group in
            
            for (index, step) in steps.enumerated() {
                group.addTask {
                    let startTime = Date()
                    let result: (status: VerificationStatus, reason: LocalizedStringResource?)
                    
                    // Await the check. Because these tasks run concurrently, long-running
                    // suspensions (like permission prompts or sleep polling) won't block the others.
                    switch step.type {
                    case .locationAuthorization:
                        result = await self.checkLocation()
                    case .stereoAudio:
                        result = await self.checkStereoAudio()
                    case .audioRouting:
                        result = await self.checkAudioRouting()
                    case .neuralEngine:
                        result = await self.checkNeuralEngine()
                    case .storage:
                        result = await self.checkStorage()
                    case .orientation:
                        // Still requires 'await' because self is strictly bound to @MainActor
                        result = await self.checkOrientation()
                    }
                    
                    let elapsed = Date().timeIntervalSince(startTime)
                    let minimumDisplayTime: TimeInterval = Double.random(in: 0.5...2.0)
                    
                    if elapsed < minimumDisplayTime {
                        try? await Task.sleep(for: .seconds(minimumDisplayTime - elapsed))
                    }
                    
                    // Return the index alongside the payload so we know which task to update
                    return (index, result.status, result.reason)
                }
            }
            
            // As each concurrent task finishes, update the specific step's state.
            // This loop inherently runs on the @MainActor, making UI updates safe.
            for await (index, status, reason) in group {
                self.steps[index].status = status
                
                if let unwrappedReason = reason {
                    // 👇 Check the flag before appending the settings prompt
                    if self.steps[index].isPermissionRelated {
                        let combinedString: LocalizedStringResource = "\(String(localized: unwrappedReason))\n\(String(localized: AppGlobals.openSystemSettingsForApp))"
                        self.steps[index].failureReason = combinedString
                    } else {
                        self.steps[index].failureReason = unwrappedReason
                    }
                } else {
                    self.steps[index].failureReason = nil
                }
            }
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
