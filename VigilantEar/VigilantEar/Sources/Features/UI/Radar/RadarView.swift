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
                
                // Background rings + labels (rotate with heading)
                drawRadarGrid(ctx: ctx, center: center, radius: radius, heading: micManager.currentHeading)
                
                // Clean sweep line
                drawSweep(ctx: ctx, center: center, radius: radius, angle: sweepAngle)
                
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
            
            // Test mode banner
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
    
    private func drawRadarGrid(ctx: GraphicsContext, center: CGPoint, radius: CGFloat, heading: Double) {
        // Rings
        for i in 1...4 {
            let r = radius * CGFloat(i) / 4
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path { $0.addEllipse(in: rect) }, with: .color(.green.opacity(0.15)), lineWidth: 1)
        }
        
        // Thin crosshairs (rotated correctly)
        let rot = -heading * .pi / 180
        let v1 = rotatePoint(center, by: rot, radius: -radius)
        let v2 = rotatePoint(center, by: rot, radius: radius)
        ctx.stroke(Path { $0.move(to: v1); $0.addLine(to: v2) }, with: .color(.green.opacity(0.3)), lineWidth: 1)
        
        let h1 = rotatePoint(center, by: rot + .pi/2, radius: -radius)
        let h2 = rotatePoint(center, by: rot + .pi/2, radius: radius)
        ctx.stroke(Path { $0.move(to: h1); $0.addLine(to: h2) }, with: .color(.green.opacity(0.3)), lineWidth: 1)
        
        // Cardinal labels
        let labels = [("N", -90.0), ("E", 0.0), ("S", 90.0), ("W", 180.0)]
        for (label, deg) in labels {
            let angle = Angle.degrees(deg - heading)
            let pos = polarToCartesian(angle: angle.degrees, radius: radius + 32, center: center)
            ctx.draw(
                Text(label)
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(.green),
                at: pos,
                anchor: .center
            )
        }
    }
    
    private func drawSweep(ctx: GraphicsContext, center: CGPoint, radius: CGFloat, angle: Double) {
        let path = Path { path in
            path.move(to: center)
            let end = polarToCartesian(angle: angle - 90, radius: radius, center: center)
            path.addLine(to: end)
        }
        ctx.stroke(path, with: .color(.green), lineWidth: 2.5)
    }
    
    private func polarToCartesian(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let rad = (angle - 90) * .pi / 180
        return CGPoint(x: center.x + radius * cos(rad), y: center.y + radius * sin(rad))
    }
    
    private func rotatePoint(_ center: CGPoint, by angle: Double, radius: CGFloat) -> CGPoint {
        let rad = angle
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
