import Foundation
import Observation
import CoreML
import UserNotifications
import AVFAudio

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
            //group.addTask { await (.criticalAlerts, self.checkEntitlements()) }
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
            // Updated 'allowBluetooth' to 'allowBluetoothHFP' for Swift 6 compliance
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetoothHFP, .defaultToSpeaker]
            )
            // Force the orientation to use the built-in wide stereo field
            try session.setPreferredInputOrientation(.landscapeRight)
            try session.setActive(true)
            
            let channelCount = session.inputNumberOfChannels
            print("Hardware reported \(channelCount) channels.") // VigilantEar needs 2+
            
            return session.inputNumberOfChannels >= 2 ? .passed : .failed
        } catch {
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
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        // Check for the specific Critical Alert authorization
        if settings.criticalAlertSetting == .enabled {
            return .passed
        } else {
            // You might want to trigger a permission request here if it's .notDetermined
            return .failed
        }
        
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
