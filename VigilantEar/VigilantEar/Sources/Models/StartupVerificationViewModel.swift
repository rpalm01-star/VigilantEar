import Foundation
import Observation
import CoreML
import UserNotifications
import AVFAudio
import UserNotifications

enum VerificationStatus {
    case pending, running, passed, failed
}

struct VerificationTask: Identifiable {
    let id = UUID()
    let type: VerificationType
    var status: VerificationStatus = .pending
}

enum VerificationType: String {
    case micArray = "Microphone Array (TDOA)"
    case neuralEngine = "Neural Engine Capabilities"
    case criticalAlerts = "Critical Alert Entitlements"
    case storage = "Secure Storage Access"
}

@Observable
@MainActor
class StartupVerificationViewModel {
    // UI state properties
    var steps: [VerificationTask] = [
        VerificationTask(type: .micArray),
        VerificationTask(type: .neuralEngine),
        VerificationTask(type: .criticalAlerts),
        VerificationTask(type: .storage)
    ]
    
    var isFinished = false
    
    func runDiagnostics() async {
        for i in steps.indices {
            steps[i].status = .running
        }
        
        await withTaskGroup(of: (VerificationType, VerificationStatus).self) { group in
            group.addTask { await (.micArray, self.checkMicArray()) }
            group.addTask { await (.neuralEngine, self.checkNeuralEngine()) }
            group.addTask { await (.criticalAlerts, self.checkEntitlements()) }
            group.addTask { await (.storage, self.checkStorage()) }
            
            for await (type, status) in group {
                if let index = steps.firstIndex(where: { $0.type == type }) {
                    steps[index].status = status
                }
            }
        }
        
        isFinished = true
    }
    
    private func checkMicArray() async -> VerificationStatus {
        let session = AVAudioSession.sharedInstance()
        
        // In Swift 6 / iOS 17+, use AVAudioApplication for a cleaner async check
        let status = AVAudioApplication.shared.recordPermission
        
        switch status {
        case .granted:
            return await configureAndVerifyChannels(session)
        case .denied:
            return .failed
        case .undetermined:
            // This triggers the system popup correctly for Swift 6
            let granted = await AVAudioApplication.requestRecordPermission()
            if granted {
                return await configureAndVerifyChannels(session)
            } else {
                return .failed
            }
        @unknown default:
            return .failed
        }
    }
    
    private func configureAndVerifyChannels(_ session: AVAudioSession) async -> VerificationStatus {
        do {
            // 1. Setup the high-fidelity recording environment
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetoothHFP, .defaultToSpeaker])
            
            // 2. Safely grab the built-in mic
            guard let inputs = session.availableInputs,
                  let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) else {
                return .failed
            }
            
            // 3. Find a data source that likes to point Front or Back
            var stereoSource: AVAudioSessionDataSourceDescription? = nil
            if let sources = builtInMic.dataSources {
                for source in sources {
                    // Use 'orientation' to find the right physical mic
                    if source.orientation == AVAudioSession.Orientation.front || source.orientation == AVAudioSession.Orientation.back {
                        stereoSource = source
                        
                        // Extra Credit: Tell the mic to use a Stereo polar pattern if available
                        if let patterns = source.supportedPolarPatterns,
                           patterns.contains(.stereo) {
                            try source.setPreferredPolarPattern(.stereo)
                        }
                        break
                    }
                }
            }
            
            // 4. Apply the configuration
            if let targetSource = stereoSource {
                try builtInMic.setPreferredDataSource(targetSource)
                try session.setPreferredInput(builtInMic)
                try session.setPreferredInputOrientation(.landscapeRight)
            }
            
            try session.setActive(true)

            // 5. The Moment of Truth for VigilantEar
            let channelCount = session.inputNumberOfChannels
            print("DEBUG: Hardware reported \(channelCount) channels.")
            
            return channelCount >= 2 ? .passed : .failed
        } catch {
            print("DEBUG: Audio Session Configuration Failed: \(error.localizedDescription)")
            return .failed
        }
    }
    
    private func checkNeuralEngine() async -> VerificationStatus {
        // We check if the device supports the 'computeDevice' API (iOS 17+)
        // and specifically look for Neural Engine availability.
        let devices = MLComputeDevice.allComputeDevices
        let hasANE = devices.contains { device in
            if case .neuralEngine = device { return true }
            return false
        }
        
        return hasANE ? .passed : .failed
    }
    
    private func checkEntitlements() async -> VerificationStatus {
#if DEBUG
        // While waiting for Apple's approval, we'll force a pass in Debug mode
        print("DEBUG: Bypassing Critical Alert check while awaiting Apple approval.")
        return .passed
#else
        let center = UNUserNotificationCenter.current()
        
        // 1. Check current settings
        let settings = await center.notificationSettings()
        
        // 2. If already enabled, we are good
        if settings.criticalAlertSetting == .enabled {
            return .passed
        }
        
        // 3. If not determined or denied, trigger the request
        do {
            // You MUST include .criticalAlert in the options list
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
            
            if granted {
                // Re-check specifically for the critical alert bit
                let newSettings = await center.notificationSettings()
                return newSettings.criticalAlertSetting == .enabled ? .passed : .failed
            } else {
                return .failed
            }
        } catch {
            print("Notification Auth Error: \(error.localizedDescription)")
            return .failed
        }
#endif
    }
    
    private func checkStorage() async -> VerificationStatus {
        let fileManager = FileManager.default
        
        // 1. Get the URL for the app's document directory
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .failed
        }
        
        do {
            // 2. Perform a "Can I actually write here?" test
            let testFileURL = documentsURL.appendingPathComponent(".storage_check_vear")
            let testData = "VigilantEar_Check".data(using: .utf8)!
            
            try testData.write(to: testFileURL)
            try fileManager.removeItem(at: testFileURL)
            
            // 3. Check for available disk space (requiring at least 100MB for logs/buffers)
            let values = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage, capacity > 100 * 1024 * 1024 {
                return .passed
            } else {
                // Not enough space for acoustic logging
                return .failed
            }
        } catch {
            return .failed
        }
    }
}
