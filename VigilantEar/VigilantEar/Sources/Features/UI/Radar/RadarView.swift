import SwiftUI

struct RadarView: View {
    @Environment(MicrophoneManager.self) private var viewModel
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Radar Background (Grid) - Rotates with compass
                RadarBackgroundView()
                    .rotationEffect(.degrees(-viewModel.currentHeading))
                
                // 2. Dynamic Sweep Animation
                RadarSweepView()
                
                // 3. Acoustic Event Plotting
                ForEach(viewModel.events) { event in
                    RadarDotView(
                        event: event,
                        size: geometry.size,
                        isTestMode: viewModel.isTestMode,
                        userHeading: viewModel.currentHeading
                    )
                    .transition(.opacity.combined(with: .scale))
                    .id(event.timestamp)
                }
            }
            .background(Color.black)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.green.opacity(0.2), lineWidth: 1))
            .contentShape(Circle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded {
                        viewModel.toggleTestMode()
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
    }
    
    // MARK: - Sub-Views
    struct RadarDotView: View {
        let event: SoundEvent
        let size: CGSize
        let isTestMode: Bool
        let userHeading: Double
        
        var body: some View {
            // Use the event's internal distance. If it's missing, default to 0.75
            // so it stays on the 3rd ring until we update the SoundEvent model.
            let eventDistance = event.distance
            
            let relativeAngle = event.bearing - userHeading
            
            // Pass eventDistance instead of a hardcoded 0.75
            let position = calculatePosition(for: relativeAngle, proximity: eventDistance, in: size)
            
            let age = Date().timeIntervalSince(event.timestamp)
            let opacity = max(0.0, 1.0 - age / 2.5)
            
            Circle()
                .fill(determineColor())
                .frame(width: 12, height: 12)
                .shadow(color: determineColor().opacity(0.9), radius: 8)
                .opacity(opacity)
                .position(position) // This uses the CGPoint from calculatePosition
        }
        
        private func determineColor() -> Color {
            if isTestMode {
                // FIXED: Use 'bearing' instead of 'angle'
                let normalizedAngle = Int(event.bearing.truncatingRemainder(dividingBy: 360) + 360) % 360
                switch normalizedAngle {
                case 0..<90:    return .red
                case 90..<180:  return .green
                case 180..<270: return .yellow
                case 270..<360: return .blue
                default:        return .white
                }
            } else {
                return dynamicColor(for: event)
            }
        }
        
        private func calculatePosition(for angle: Double, proximity: Double, in size: CGSize) -> CGPoint {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            
            // The maximum radius is half the width of the view
            let maxRadius = size.width / 2
            let actualRadius = maxRadius * CGFloat(proximity)
            
            // Adjust angle so 0 degrees is North/Up
            let adjustedAngle = CGFloat(angle - 90) * .pi / 180
            
            return CGPoint(
                x: center.x + actualRadius * cos(adjustedAngle),
                y: center.y + actualRadius * sin(adjustedAngle)
            )
        }
        
        // FIXED: Doppler-based dynamic color
        private func dynamicColor(for event: SoundEvent) -> Color {
            // Red means it is approaching you. Cyan means it is receding/driving away.
            if event.isApproaching {
                return Color.red
            } else {
                return Color.cyan
            }
        }
    }
    
    struct RadarBackgroundView: View {
        var body: some View {
            ZStack {
                // 1. Circular Grid Lines
                ForEach(1...4, id: \.self) { i in
                    Circle()
                        .stroke(Color.green.opacity(0.15), lineWidth: 1)
                        .scaleEffect(CGFloat(i) * 0.25)
                }
                
                // 2. Axis Lines (N-S and E-W)
                Rectangle().fill(Color.green.opacity(0.3)).frame(width: 1)
                Rectangle().fill(Color.green.opacity(0.1)).frame(height: 1)
                
                // 3. Directional "Indicator Pods" pushed to the outer-outer orbit
                Group {
                    DirectionPod(label: "N").offset(y: -190)
                    DirectionPod(label: "S").offset(y: 190)
                    DirectionPod(label: "E").offset(x: 190)
                    DirectionPod(label: "W").offset(x: -190)
                }
            }
        }
    }
    
    struct DirectionPod: View {
        let label: String
        
        var body: some View {
            ZStack {
                // The "Pod" Circle
                Circle()
                    .fill(Color.black) // Masks the grid line underneath
                    .frame(width: 24, height: 24)
                
                Circle()
                    .stroke(Color.green.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
                
                // The Letter
                Text(label)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.green)
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
