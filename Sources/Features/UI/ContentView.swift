import SwiftUI

struct ContentView: View {
    // Injected from VigilantEarApp.swift
    @Bindable var micManager: MicrophoneManager
    
    var body: some View {
        VStack(spacing: 40) {
            Text("VigilantEar Research")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            // Decibel Visualizer
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, (micManager.currentDecibels + 160) / 160)))
                    .stroke(decibelColor, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.interactiveSpring, value: micManager.currentDecibels)
                
                VStack {
                    Text("\(Int(micManager.currentDecibels))")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                    Text("dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 250, height: 250)
            
            // Placeholder for the "Liquid Glass" Arrow
            Image(systemName: "arrow.up.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundStyle(.blue.gradient)
                .rotationEffect(.degrees(micManager.estimatedAngle))
                .animation(.spring, value: micManager.estimatedAngle)
            
            Text("Monitoring for Sirens/Motorcycles...")
                .font(.footnote)
                .italic()
        }
        .padding()
    }
    
    // Dynamic color logic based on noise safety levels
    private var decibelColor: Color {
        if micManager.currentDecibels > -60 { return .red }
        if micManager.currentDecibels > -90 { return .orange }
        return .green
    }
}
