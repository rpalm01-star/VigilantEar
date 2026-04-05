import SwiftUI

struct RadarView: View {
    let events: [SoundEvent]
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2
            
            ZStack {
                // 1. Background Grid (Concentric Circles representing dB thresholds)
                ForEach(1...4, id: \.self) { i in
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        .frame(width: (radius * 2) * CGFloat(i) / 4)
                }
                
                // 2. User Origin (The Research Point)
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .blue.opacity(0.8), radius: 4)
                
                // 3. Dynamic Acoustic Objects
                ForEach(events) { event in
                    ZStack {
                        // A. The History Trail (Breadcrumbs)
                        // Only show trails for high-confidence "Vessels" (Motorcycles/Sirens)
                        if !event.isAmbient {
                            ForEach(event.history) { crumb in
                                Circle()
                                    .fill(event.color)
                                    .opacity(crumb.opacity * 0.3)
                                    .frame(width: event.visualSize * 0.4, height: event.visualSize * 0.4)
                                    .offset(y: -CGFloat(crumb.radialProx) * radius)
                                    .rotationEffect(.degrees(crumb.angle))
                            }
                        }
                        
                        // B. The Active Sound "Head"
                        Circle()
                            .fill(event.color.gradient)
                            .frame(width: event.visualSize, height: event.visualSize)
                            // Ambient noise gets the "Grey Blob" treatment
                            .opacity(event.isAmbient ? 0.3 : 1.0)
                            .blur(radius: event.isAmbient ? 12 : 0)
                            
                            // Proximity Mapping: Border (1.0) to Center (0.0)
                            .offset(y: -CGFloat(event.radialProx) * radius)
                            .rotationEffect(.degrees(event.angle))
                            
                            // Dynamic Animations for M4 120Hz ProMotion
                            .animation(.smooth(duration: 0.6), value: event.radialProx)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: event.angle)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black) // High-contrast for research
        }
    }
}
