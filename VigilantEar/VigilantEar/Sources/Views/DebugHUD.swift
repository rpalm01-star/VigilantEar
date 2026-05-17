// DebugHUD.swift
// VigilantEar
//
// Created by Robert Palmer on 4/26/26.

import SwiftUI
import Network
import Combine

// Minimal monitor to track connectivity status
class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = false
    @Published var activeInterface = "WAIT"
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isWiFi = path.usesInterfaceType(.wifi)
            let isCellular = path.usesInterfaceType(.cellular)
            let isWired = path.usesInterfaceType(.wiredEthernet)
            
            let trulyConnected = (path.status == .satisfied) && (isWiFi || isCellular)
            
            var iface = "NONE"
            if path.status != .satisfied { iface = "DEAD" }
            else if isWiFi { iface = "WIFI" }
            else if isCellular { iface = "CELL" }
            else if isWired { iface = "USB" }
            else { iface = "OTHER" }
            
            DispatchQueue.main.async {
                self?.activeInterface = iface
                if self?.isConnected != trulyConnected {
                    self?.isConnected = trulyConnected
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}

struct DebugHUD: View {
    @EnvironmentObject var ui: UIManager
    @Bindable var manager: MicrophoneManager
    @Bindable var roadManager: RoadManager
    
    @ObservedObject private var monitor = TelemetryManager.shared
    @StateObject private var network = NetworkMonitor()
    
    @State private var isCloudLoggingEnabled: Bool = AppGlobals.logToCloud
    @State private var currentTime = String.empty
    
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    private let f1: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a z"
        return formatter
    }()
    
    init() {
        self.manager = DependencyContainer.shared.microphoneManager
        self.roadManager = DependencyContainer.shared.roadManager
    }
    
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
                Text(AppGlobals.telemetryLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DependencyContainer.shared.debugSimulationManager.isEmergencySimulationRunning ? .red : (isCloudLoggingEnabled ? .cyan : .green))
            }
            
            HStack(spacing: 5) {
                Text(verbatim: "BAT:")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text(Double(monitor.batteryLevel) / 100, format: .percent)
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
                Text(verbatim: "(\(manager.activeMicCount))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(manager.activeMicCount > 0 ? .green : .red)
            }
            
            HStack(spacing: 5) {
                Text(verbatim: "NET:")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text(network.isConnected ? AppGlobals.ONLINE : AppGlobals.OFFLINE)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(network.isConnected ? .green : .red)
            }
            
            HStack(spacing: 5) {
                Text(verbatim: "NOW:")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text(verbatim: currentTime)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.green)
                    .fixedSize()
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.spring(duration: 0.3), value: currentTime)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: (preferredLanguage == "en" || preferredLanguage == "es" ? 140 : 160), alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    DependencyContainer.shared.debugSimulationManager.isEmergencySimulationRunning
                    ? Color.red.opacity(0.65)
                    : (isCloudLoggingEnabled ? Color.cyan.opacity(0.65) : Color.clear),
                    lineWidth: 3
                )
                .fill(
                    DependencyContainer.shared.debugSimulationManager.isEmergencySimulationRunning
                    ? Color.red.opacity(0.30)
                    : Color.clear
                )
        )
        .compositingGroup()
        .drawingGroup(opaque: true)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .opacity(ui.isMenuOpen ? 0 : 0.35)     // ← now matches the bottom button bar dimness
        .shadow(radius: 3)
        .environment(\.locale, Locale(identifier: preferredLanguage))
        .onAppear {
            monitor.start()
            startClock()
        }
        #if DEBUG
        .onTapGesture(count: 1) { handleSingleTap() }
        .onTapGesture(count: 2) { handleDoubleTap() }
        #endif
    }
    
#if DEBUG
    private func handleSingleTap() {
        guard AppGlobals.isDebugDevice else { return }
        AppGlobals.doLog(message: "✅ Single-tap accepted: isDebugDevice: \(AppGlobals.isDebugDevice)", step: "DebugHUD.handleSingleTap")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isCloudLoggingEnabled.toggle()
        AppGlobals.logToCloud = isCloudLoggingEnabled
    }

    private func handleDoubleTap() {
        guard AppGlobals.isDebugDevice else { return }
        AppGlobals.doLog(message: "✅ Double-tap accepted: isDebugDevice: \(AppGlobals.isDebugDevice)", step: "DebugHUD.handleDoubleTap")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let panel = SoundProfilesPanelView()
        let hostingController = UIHostingController(rootView: panel)
        hostingController.modalPresentationStyle = .pageSheet
        if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(hostingController, animated: true)
        }
    }
#endif
    
    private func startClock() {
        f1.locale = Locale(identifier: preferredLanguage)
        if (preferredLanguage == "en" || preferredLanguage == "es") {
            f1.amSymbol = "AM"
            f1.pmSymbol = "PM"
        } else {
            f1.amSymbol = nil
            f1.pmSymbol = nil
        }
        
        currentTime = f1.string(from: Date())
        
        let now = Date()
        let calendar = Calendar.current
        let currentSecond = calendar.component(.second, from: now)
        let nanos = calendar.component(.nanosecond, from: now)
        let preciseDelay = 60.0 - Double(currentSecond) - Double(nanos) / 1_000_000_000.0
        
        Timer.scheduledTimer(withTimeInterval: preciseDelay, repeats: false) { _ in
            self.currentTime = self.f1.string(from: Date())
            
            Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
                self.currentTime = self.f1.string(from: Date())
            }
        }
    }
}

