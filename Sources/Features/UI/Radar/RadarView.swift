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
                ForEach(events) { event in
                    // Only render if the event is not classified as ambient noise
                    if !event.classification.contains("Ambient") {
                        RadarDotView(
                            event: event,
                            size: geometry.size
                        )
                        .transition(.opacity.combined(with: .scale))
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
}

// MARK: - Subviews

struct RadarDotView: View {
    let event: SoundEvent
    let size: CGSize
    
    var body: some View {
        let position = calculatePosition(for: event, in: size)
        
        Circle()
            .fill(event.confidence > 0.8 ? Color.red : Color.yellow)
            .frame(width: 8, height: 8)
            .shadow(color: .green, radius: 4)
            .position(position)
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
