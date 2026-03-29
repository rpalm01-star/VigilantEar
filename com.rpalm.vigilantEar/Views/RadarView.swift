import SwiftUI

struct RadarView: View {
    let events: [SoundEvent]
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2
            
            ZStack {
                // 1. Background Grid (Concentric Circles)
                ForEach(1...4, id: \.self) { i in
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        .frame(width: (radius * 2) * CGFloat(i) / 4)
                }
                
                // 2. User Location (The Origin)
                Circle()
                    .fill(event.color)
                    .opacity(event.isAmbient ? 0.3 : 1.0)
                    .blur(radius: event.isAmbient ? 10 : 0) // The "Blob" effect
                    .frame(width: 12, height: 12)
                    .shadow(color: .blue.opacity(0.5), radius: 5)
                
                // 3. Dynamic Sound Dots
                ForEach(events) { event in
                    Circle()
                        .fill(event.color.gradient)
                        .frame(width: event.visualSize, height: event.visualSize)
                        // Position logic: Border (1.0) to Center (0.0)
                        .offset(y: -CGFloat(event.radialProx) * radius)
                        .rotationEffect(.degrees(event.angle))
                        .animation(.smooth(duration: 0.5), value: event.radialProx)
                        .animation(.spring(), value: event.angle)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
