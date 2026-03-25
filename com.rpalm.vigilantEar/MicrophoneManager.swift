import Foundation
import AVFoundation
import Observation

@Observable
class MicrophoneManager {
    private var audioRecorder: AVAudioRecorder?
    var currentDecibels: Float = -160.0 // Silence is -160, max is 0
    
    init() {
        setupMicrophone()
    }
    
    func setupMicrophone() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
            try session.setActive(true)
            
            let url = URL(fileURLWithPath: "/dev/null") // We don't need to save the file
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 2, // Crucial for your TDOA/Directional math later
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            // Start a timer to check the volume 10 times a second
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                self.updateMeters()
            }
        } catch {
            print("Failed to set up microphone: \(error)")
        }
    }
    
    private func updateMeters() {
        audioRecorder?.updateMeters()
        // We take the average power from the first channel
        currentDecibels = audioRecorder?.averagePower(forChannel: 0) ?? -160.0
    }
}
