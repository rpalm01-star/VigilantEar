import Foundation

struct MockAcousticEvent {
    let frequency: Double  // in Hz
    let amplitude: Float   // 0.0 to 1.0
    let angleOfArrival: Double // -180 to 180 degrees
}

class MockDataGenerator {
    /// Simulates a motorcycle approaching from the left and passing to the right
    static func generateMotorcyclePassby() -> [MockAcousticEvent] {
        var events: [MockAcousticEvent] = []
        
        for i in 0...50 { // 5 seconds of data at 10Hz
            let progress = Double(i) / 50.0
            
            // Doppler: Frequency drops as it passes
            let freq = 440.0 * (1.1 - (0.2 * progress)) 
            
            // TDOA: Angle shifts from -90 to +90
            let angle = -90.0 + (180.0 * progress)
            
            // Volume: Peaks in the middle (at 2.5 seconds)
            let amp = Float(1.0 - abs(0.5 - progress) * 2)
            
            events.append(MockAcousticEvent(frequency: freq, amplitude: amp, angleOfArrival: angle))
        }
        return events
    }
}
