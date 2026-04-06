import SwiftUI

struct RadarView: View {
    /// The collection of acoustic events captured by the MicrophoneManager
    let events: [SoundEvent]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Radar Background (Circular Grids)
                RadarBackgroundView()
                
                // 2. Dynamic Sweep Animation
                RadarSweepView()
                
                // 3. Acoustic Event Plotting
                // FIX: Standard ForEach for Identifiable arrays (no '$' or Binding)
                // Replace your current ForEach with this:
                ForEach(events) { event in
                    if !event.classification.contains("Ambient") {
                        RadarDotView(
                            event: event,
                            size: geometry.size
                        )
                        .transition(.opacity.combined(with: .scale))
                        .id(event.id)                    // ← important: forces fresh view every time
                    }
                }
            }
            .background(Color.black)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.green.opacity(0.2), lineWidth: 1))
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
    }
    
    struct RadarDotView: View {
        let event: SoundEvent
        let size: CGSize
        
        // ←←← TUNE THIS NUMBER until left/right feel correct
        // Start with -90. Try -75, -105, -120, -60 etc.
        private let angleOffset: Double = -90.0
        
        var body: some View {
            let position = calculatePosition(for: event, in: size)
            let age = Date().timeIntervalSince(event.timestamp)
            let opacity = max(0.0, 1.0 - age / 2.5)
            
            Circle()
                .fill(dynamicColor(for: event))
                .frame(width: 10, height: 10)
                .shadow(color: dynamicColor(for: event).opacity(0.9), radius: 8)
                .scaleEffect(1.0)  // flash is already in the parent view
                .opacity(opacity)
                .position(position)
        }
        
        private func calculatePosition(for event: SoundEvent, in size: CGSize) -> CGPoint {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = (size.width / 2) * CGFloat(event.proximity)
            
            let correctedAngle = (event.angle + angleOffset) * (.pi / 180)
            
            return CGPoint(
                x: center.x + radius * cos(correctedAngle),
                y: center.y + radius * sin(correctedAngle)
            )
        }
        
        private func dynamicColor(for event: SoundEvent) -> Color {
            let freq = Double(event.frequency)
            let confidence = Double(event.confidence)
            
            let hue: Double = {
                if freq < 200 { return 0.0 }
                else if freq < 800 { return 0.08 }
                else if freq < 1500 { return 0.15 }
                else if freq < 3000 { return 0.55 }
                else { return 0.75 }
            }()
            
            let saturation = 0.8 + (confidence * 0.2)
            let brightness = 0.9
            return Color(hue: hue, saturation: saturation, brightness: brightness)
        }
    }
    
    private func calculatePosition(for event: SoundEvent, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = (size.width / 2) * CGFloat(event.proximity)
        let angle = CGFloat(event.angle) * (.pi / 180)
        
        return CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }
    
    /// Dynamic color calculated from the sound itself (frequency + confidence)
    private func dynamicColor(for event: SoundEvent) -> Color {
        let freq = Double(event.frequency)
        let confidence = Double(event.confidence)
        
        // Hue based on dominant frequency (low = red/orange, high = blue/purple)
        let hue: Double = {
            if freq < 200 { return 0.0 }           // deep red
            else if freq < 800 { return 0.08 }     // orange
            else if freq < 1500 { return 0.15 }    // yellow
            else if freq < 3000 { return 0.55 }    // cyan
            else { return 0.75 }                   // purple/blue
        }()
        
        // Brightness & saturation modulated by confidence
        let saturation = 0.8 + (confidence * 0.2)
        let brightness = 0.9
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
    
    
    struct RadarBackgroundView: View {
        var body: some View {
            ZStack {
                ForEach(1...4, id: \.self) { i in
                    Circle()
                        .stroke(Color.green.opacity(0.15), lineWidth: 1)
                        .scaleEffect(CGFloat(i) * 0.25)
                }
                
                // Axis Lines
                Rectangle().fill(Color.green.opacity(0.1)).frame(width: 1)
                Rectangle().fill(Color.green.opacity(0.1)).frame(height: 1)
            }
        }
    }
    
    struct RadarSweepView: View {
        @State private var rotation: Double = 0
        
        var body: some View {
            AngularGradient(
                gradient: Gradient(colors: [.green.opacity(0.5), .clear]),
                center: .center
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
    
}
