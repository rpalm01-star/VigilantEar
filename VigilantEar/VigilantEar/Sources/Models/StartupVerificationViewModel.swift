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
    
    private func checkMicArray() async -> (status: VerificationStatus, reason: String?) {
        let session = AVAudioSession.sharedInstance()
        
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .denied { return (.failed, "Microphone permission denied") }
        if permission == .undetermined {
            guard await AVAudioApplication.requestRecordPermission() else {
                return (.failed, "Microphone permission denied")
            }
        }
        
        do {
            // 1. Switch to videoRecording mode to allow spatial/stereo DSP
            try session.setCategory(.playAndRecord,
                                    mode: .videoRecording,
                                    options: [.defaultToSpeaker, .mixWithOthers])
            
            // 2. Activate first to unlock hardware routing
            try session.setActive(true)
            
            guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
                return (.passed, "No built-in mic detected")
            }
            
            guard let sources = builtInMic.dataSources,
                  let stereoSource = sources.first(where: { $0.supportedPolarPatterns?.contains(.stereo) == true }) else {
                return (.passed, "Stereo hardware not found on this device")
            }
            
            // 3. Apple's required sequence: Source -> Orientation -> Pattern
            try builtInMic.setPreferredDataSource(stereoSource)
            try session.setPreferredInputOrientation(.portrait)
            try stereoSource.setPreferredPolarPattern(.stereo)
            
            // 4. Request the 2 channels
            try session.setPreferredInputNumberOfChannels(2)
            
            // Give hardware a moment to settle
            try await Task.sleep(for: .milliseconds(400))
            
            let channelCount = session.inputNumberOfChannels
            try? session.setActive(false)
            
            if channelCount >= 2 {
                return (.passed, nil)
            } else {
                return (.passed, "Mono detected. Hardware rejected stereo configuration.")
            }
        } catch {
            try? session.setActive(false)
            return (.passed, "Audio session warning: \(error.localizedDescription)")
        }
    }
    
}
