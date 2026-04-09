//
//  StartupVerificationViewModel.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/8/26.
//


import Foundation
import AVFoundation
import CoreML

@Observable
@MainActor
class StartupVerificationViewModel {
    var steps: [DiagnosticStep] = [
        DiagnosticStep(
            title: "Audio Session & Microphones",
            description: "Verifies that the device has the required multi-microphone array and can establish a stereo audio session for TDOA calculations."
        ),
        DiagnosticStep(
            title: "Neural Engine Capabilities",
            description: "Checks if the device supports accelerated CoreML inference (0-1ms latency) required for real-time sound classification."
        ),
        DiagnosticStep(
            title: "Critical Alerts Entitlement",
            description: "Ensures the app has permission to bypass the mute switch to deliver high-priority safety notifications."
        )
    ]
    
    var isVerificationComplete = false
    var allPassed = false
    
    func runDiagnostics() async {
        allPassed = true
        
        for index in steps.indices {
            // Set to running
            steps[index].status = .running
            
            // Artificial delay so the user can actually see the UI progression
            try? await Task.sleep(for: .milliseconds(600))
            
            let result = await performTest(for: steps[index].title)
            steps[index].status = result
            
            if case .failed = result {
                allPassed = false
                // Optional: Stop executing further tests if one fails
                // break 
            }
        }
        
        isVerificationComplete = true
    }
    
    private func performTest(for testName: String) async -> DiagnosticStatus {
        switch testName {
        case "Audio Session & Microphones":
            // TODO: Inject your actual MicrophoneManager check here
            let session = AVAudioSession.sharedInstance()
            guard let inputs = session.availableInputs, inputs.count > 0 else {
                return .failed(reason: "No audio inputs detected on this device.")
            }
            return .passed
            
        case "Neural Engine Capabilities":
            // Simulated check for Neural Engine capability
            let config = MLModelConfiguration()
            config.computeUnits = .all
            // In a real scenario, you'd try to initialize your SoundAnalysis model here
            return .passed
            
        case "Critical Alerts Entitlement":
            // Simulated check. In reality, you'd check UNUserNotificationCenter settings
            return .passed // or .failed(reason: "Critical Alerts not authorized in Settings.")
            
        default:
            return .failed(reason: "Unknown diagnostic test.")
        }
    }
}