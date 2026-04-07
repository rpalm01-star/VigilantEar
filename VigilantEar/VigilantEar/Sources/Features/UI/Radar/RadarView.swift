import SwiftUI

struct RadarView: View {
    let events: [SoundEvent]
    @ObservedObject var viewModel: MicrophoneManager
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Radar Background (Grid) - Rotates with compass
                RadarBackgroundView()
                    .rotationEffect(.degrees(-viewModel.currentHeading))
                
                // 2. Dynamic Sweep Animation
                RadarSweepView()
                
                // 3. Acoustic Event Plotting
                ForEach(events) { event in
                    if !event.classification.contains("Ambient") {
                        RadarDotView(
                            event: event,
                            size: geometry.size,
                            isTestMode: viewModel.isTestMode,
                            userHeading: viewModel.currentHeading
                        )
                        .transition(.opacity.combined(with: .scale))
                        .id(event.id)
                    }
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
            // Apply world-relative offset
            let relativeAngle = event.angle - userHeading
            let position = calculatePosition(for: relativeAngle, proximity: event.proximity, in: size)
            
            let age = Date().timeIntervalSince(event.timestamp)
            let opacity = max(0.0, 1.0 - age / 2.5)
            
            Circle()
                .fill(determineColor())
                .frame(width: 10, height: 10)
                .shadow(color: determineColor().opacity(0.9), radius: 8)
                .opacity(opacity)
                .position(position)
        }
        
        private func determineColor() -> Color {
            if isTestMode {
                let normalizedAngle = Int(event.angle.truncatingRemainder(dividingBy: 360) + 360) % 360
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
        
        // FIXED: Added missing parenthesis and closing braces
        private func calculatePosition(for angle: Double, proximity: Double, in size: CGSize) -> CGPoint {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = (size.width / 2) * CGFloat(proximity)
            let angleInRadians = (CGFloat(angle) * .pi / 180)
            
            return CGPoint(
                x: center.x + radius * cos(angleInRadians),
                y: center.y - radius * sin(angleInRadians)
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
            return Color(hue: hue, saturation: 0.8 + (confidence * 0.2), brightness: 0.9)
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
