import Foundation
import SwiftUI

class MockDataGenerator: ObservableObject {
    @Published var activeEvents: [SoundEvent] = []
    private var timer: Timer?
    
    func startSimulation() {
        // Create a "Motorcycle Pass-by" simulation
        var currentAngle: Double = -45.0 // Starting at 10 o'clock
        var currentDB: Float = -90.0     // Starting faint
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // 1. Update Physics (The "Swerve")
            currentAngle += 2.0
            
            // 2. Update Proximity (Approaching then Receding)
            if currentAngle < 45 {
                currentDB += 1.5 // Getting louder
            } else {
                currentDB -= 1.5 // Getting quieter
            }
            
            // 3. Create the Event
            let motorcycle = SoundEvent(
                id: UUID(uuidString: "MOTORCYCLE-01")!, // Fixed ID to update same dot
                timestamp: Date(),
                decibels: currentDB,
                frequency: 1050.0,
                confidence: 0.95,
                classification: "Motorcycle",
                angle: currentAngle
            )
            
            // 4. Update the UI state
            DispatchQueue.main.async {
                self.activeEvents = [motorcycle]
            }
            
            // Reset simulation if it goes off radar
            if currentAngle > 135 { currentAngle = -45; currentDB = -90 }
        }
    }
    
    func stop() {
        timer?.invalidate()
        activeEvents = []
    }
}
