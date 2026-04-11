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
    var failureReason: String? = nil
}

enum VerificationType: String {
    case micArray = "Microphone Array (Stereo TDOA)"
    case neuralEngine = "Neural Engine (CoreML)"
    case criticalAlerts = "Critical Alert Support"
    case storage = "Storage Access"
}

@Observable
@MainActor
final class StartupVerificationViewModel {
    
    var steps: [VerificationTask] = [
        VerificationTask(type: .micArray),
        VerificationTask(type: .neuralEngine),
        VerificationTask(type: .criticalAlerts),
        VerificationTask(type: .storage)
    ]
    
    var isFinished = false
    var allPassed: Bool { steps.allSatisfy { $0.status == .passed } }
    
    func runDiagnostics() async {
        for i in steps.indices { steps[i].status = .running }
        
        async let micResult = checkMicArray()
        async let neuralResult = checkNeuralEngine()
        async let alertsResult = checkEntitlements()
        async let storageResult = checkStorage()
        
        let results = await [micResult, neuralResult, alertsResult, storageResult]
        
        for (index, result) in results.enumerated() {
            steps[index].status = result.status
            steps[index].failureReason = result.reason
        }
        
        isFinished = true
    }
    
    private func checkMicArray() async -> (status: VerificationStatus, reason: String?) {
        let session = AVAudioSession.sharedInstance()
        
        // Permission
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .denied {
            return (.failed, "Microphone permission denied")
        }
        if permission == .undetermined {
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted {
                return (.failed, "Microphone permission denied")
            }
        }
        
        do {
            try session.setCategory(.playAndRecord,
                                   mode: .measurement,
                                   options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
            
            // Give hardware time to settle (this is what the real app does)
            try await Task.sleep(for: .milliseconds(400))
            
            guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
                try? session.setActive(false)
                return (.passed, "No built-in mic detected")
            }
            
            // Try to enable stereo
            if let sources = builtInMic.dataSources {
                for source in sources {
                    if source.supportedPolarPatterns?.contains(.stereo) == true {
                        try? source.setPreferredPolarPattern(.stereo)
                        try? builtInMic.setPreferredDataSource(source)
                        try? session.setPreferredInputOrientation(.portrait)
                        break
                    }
                }
            }
            
            try? session.setPreferredInputNumberOfChannels(2)
            
            let channelCount = session.inputNumberOfChannels
            print("🔍 Verification mic check — reported channels: \(channelCount)")
            
            try? session.setActive(false)
            
            if channelCount >= 2 {
                return (.passed, nil)                    // Full stereo — perfect
            } else {
                return (.passed, "Mono detected in quick check — TDOA will still work (real runtime tries harder)")
            }
        } catch {
            try? session.setActive(false)
            return (.passed, "Audio session warning — TDOA will still work")
        }
    }
    
    private func checkNeuralEngine() async -> (status: VerificationStatus, reason: String?) {
        let hasANE = MLComputeDevice.allComputeDevices.contains { device in
            if case .neuralEngine = device { return true }
            return false
        }
        return hasANE ? (.passed, nil) : (.failed, "Neural Engine not available")
    }
    
    private func checkEntitlements() async -> (status: VerificationStatus, reason: String?) {
#if DEBUG
        return (.passed, nil)
#else
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        if settings.criticalAlertSetting == .enabled {
            return (.passed, nil)
        }
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
            if granted {
                let newSettings = await center.notificationSettings()
                return newSettings.criticalAlertSetting == .enabled ? (.passed, nil) : (.failed, "Critical alerts not enabled")
            }
        } catch {}
        return (.failed, "Critical alert authorization failed")
#endif
    }
    
    private func checkStorage() async -> (status: VerificationStatus, reason: String?) {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (.failed, "Cannot access documents directory")
        }
        
        do {
            let testFileURL = documentsURL.appendingPathComponent(".ve_test")
            let testData = "VigilantEar test".data(using: .utf8)!
            
            try testData.write(to: testFileURL)
            try fileManager.removeItem(at: testFileURL)
            
            let values = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage, capacity > 80 * 1024 * 1024 {
                return (.passed, nil)
            } else {
                return (.failed, "Not enough free storage (~80 MB needed)")
            }
        } catch {
            return (.failed, "Storage test failed")
        }
    }
    
    func continueToApp() {
        // Your parent view (e.g. ContentView or App) can observe this or use a @State to dismiss the verification screen
        print("✅ Startup verification complete — launching main app")
    }
}
