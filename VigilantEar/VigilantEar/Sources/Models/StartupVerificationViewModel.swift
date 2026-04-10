import Foundation
import Observation

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
        try? await Task.sleep(for: .seconds(1.2))
        return .passed
    }

    private func checkNeuralEngine() async -> VerificationStatus {
        try? await Task.sleep(for: .seconds(0.8))
        return .passed
    }

    private func checkEntitlements() async -> VerificationStatus {
        try? await Task.sleep(for: .seconds(0.5))
        return .passed
    }

    private func checkStorage() async -> VerificationStatus {
        try? await Task.sleep(for: .seconds(0.4))
        return .passed
    }
}
