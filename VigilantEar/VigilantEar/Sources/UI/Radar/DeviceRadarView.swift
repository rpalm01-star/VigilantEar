//
//  DeviceRadarView.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/11/26.
//


import SwiftUI

struct DeviceRadarView: View {
    // Pass in your active sounds from the AcousticCoordinator
    var events: [SoundEvent] 
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let centerX = width / 2
            let centerY = height / 2
            
            ZStack {
                // 1. Draw the "Phone Outline" grid
                // This draws 4 concentric rounded rectangles growing outward
                ForEach(1...4, id: \.self) { ring in
                    let scale = CGFloat(ring) / 4.0
                    // Scale the corner radius so the innermost ring isn't overly round
                    RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        .frame(width: width * scale, height: height * scale)
                }
                
                // 2. Draw subtle crosshairs to define front/back/left/right
                Path { path in
                    path.move(to: CGPoint(x: centerX, y: 0))
                    path.addLine(to: CGPoint(x: centerX, y: height))
                    path.move(to: CGPoint(x: 0, y: centerY))
                    path.addLine(to: CGPoint(x: width, y: centerY))
                }
                .stroke(Color.green.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // 3. Plot the acoustic events
                ForEach(events, id: \.timestamp) { event in
                    // Convert bearing to radians (assuming 0 is Top/North)
                    let radians = CGFloat(event.bearing) * .pi / 180.0
                    
                    // Elliptical Mapping:
                    // We multiply the sine/cosine by the half-width/half-height of the screen.
                    // This stretches the "circle" into an ellipse that perfectly fits the view.
                    let xOffset = CGFloat(event.distance) * (width / 2) * sin(radians)
                    
                    // Y is inverted because in iOS, Y increases downwards
                    let yOffset = -CGFloat(event.distance) * (height / 2) * cos(radians)
                    
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 16, height: 16)
                        // Add a glow based on the UI energy we calculated earlier
                        .shadow(color: .cyan, radius: CGFloat(event.energy) * 15)
                        .position(x: centerX + xOffset, y: centerY + yOffset)
                        // Smoothly animate the dot as distance/bearing updates
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: event.distance)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: event.bearing)
                }
            }
        }
        // Give it some padding so the outer ring doesn't scrape the physical screen edge
        .padding(.horizontal, 20)
        .padding(.bottom, 40) 
    }
}