import SwiftUI
import CoreHaptics

struct RadarView: View {
    @Environment(MicrophoneManager.self) private var micManager
    
    @State private var sweepAngle: Double = 0
    @State private var engine: CHHapticEngine?
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2.1
                
                // Only rings
                for i in 1...4 {
                    let r = radius * CGFloat(i) / 4
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    ctx.stroke(Path { $0.addEllipse(in: rect) }, with: .color(.green.opacity(0.15)), lineWidth: 1)
                }
                
                // Clean sweep
                let sweepPath = Path { path in
                    path.move(to: center)
                    let end = polarToCartesian(angle: sweepAngle, radius: radius, center: center)
                    path.addLine(to: end)
                }
                ctx.stroke(sweepPath, with: .color(.green), lineWidth: 2.5)
                
                // Dots
                for event in micManager.events {
                    let relativeAngle = (event.bearing - micManager.currentHeading).truncatingRemainder(dividingBy: 360)
                    let dotPos = polarToCartesian(angle: relativeAngle, radius: radius * CGFloat(event.distance), center: center)
                    
                    let age = Date().timeIntervalSince(event.timestamp)
                    let opacity = max(0.0, 1.0 - age / 5.0)
                    let color = event.isApproaching ? Color.red : Color.cyan
                    
                    ctx.opacity = opacity
                    
                    ctx.fill(
                        Path { $0.addEllipse(in: CGRect(origin: dotPos, size: CGSize(width: 26, height: 26))) },
                        with: .color(color)
                    )
                    ctx.fill(
                        Path { $0.addEllipse(in: CGRect(origin: dotPos, size: CGSize(width: 40, height: 40))) },
                        with: .color(color.opacity(0.4))
                    )
                }
            }
            .background(Color.black)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.green.opacity(0.3), lineWidth: 3))
            .contentShape(Circle())
            
            .overlay(alignment: .top) {
                if micManager.isTestMode {
                    Text("TEST MODE ON — DOUBLE-TAP TO EXIT")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 12)
                }
            }
            
            .gesture(
                TapGesture(count: 2)
                    .onEnded { micManager.toggleTestMode() }
            )
            .onAppear {
                startHapticEngine()
                withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    sweepAngle = 360
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
    }
    
    private func polarToCartesian(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let rad = (angle - 90) * .pi / 180
        return CGPoint(x: center.x + radius * cos(rad), y: center.y + radius * sin(rad))
    }
    
    private func startHapticEngine() {
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {}
    }
    
    private func triggerDirectionalHaptic() {
        guard let engine else { return }
        let pattern = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        ], relativeTime: 0)
        
        do {
            let player = try engine.makePlayer(with: CHHapticPattern(events: [pattern], parameters: []))
            try player.start(atTime: 0)
        } catch {}
    }
}
