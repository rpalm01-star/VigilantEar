// DebugHUD.swift
// VigilantEar
//
// Created by Robert Palmer on 4/26/26.
//

import SwiftUI

struct DebugHUD: View {
    
    @Bindable var manager: MicrophoneManager
    var roadManager: RoadManager
    
    @StateObject private var monitor = TelemetryManager.shared
    @State private var isCloudLoggingEnabled: Bool = AppGlobals.logToCloud
    
    private var thermalIcon: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:   return "thermometer.low"
        case .fair:      return "thermometer.medium"
        case .serious:   return "thermometer.high"
        case .critical:  return "flame.fill"
        @unknown default: return "thermometer"
        }
    }
    
    private var thermalColor: Color {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:   return .green
        case .fair:      return .yellow
        case .serious:   return .orange
        case .critical:  return .red
        @unknown default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            
            HStack(spacing: 4) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 9))
                    .foregroundColor(isCloudLoggingEnabled ? .cyan : .green)
                
                Text("Telemetry")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isCloudLoggingEnabled ? .cyan : .green)
            }
            
            HStack(spacing: 5) {
                Text("BAT:")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text("\(monitor.batteryLevel)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(monitor.batteryLevel > 20 ? .green : .red)
                Image(systemName: thermalIcon)
                    .font(.system(size: 9))
                    .foregroundColor(thermalColor)
                if monitor.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                }
            }
            
            HStack(spacing: 5) {
                Text("MIC:")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text("\(manager.activeMicCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(manager.activeMicCount > 0 ? .green : .red)
            }
            
            HStack(spacing: 5) {
                Text("OSM:")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text("\(roadManager.cachedRoadSegments.count) roads")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(roadManager.cachedRoadSegments.isEmpty ? .red : .green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 100, alignment: .leading)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isCloudLoggingEnabled ? Color.cyan.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .opacity(0.45)
        .shadow(radius: 3)
        .onAppear { monitor.start() }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isCloudLoggingEnabled.toggle()
                AppGlobals.logToCloud = isCloudLoggingEnabled
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
}
