//  StatusPillView.swift
//  VigilantEar
//
//  Created by Robert Palmer on 5/5/26.
//

import SwiftUI

struct StatusPillView: View {
    @EnvironmentObject var ui: UIManager
    
    let coordinator = DependencyContainer.shared.acousticCoordinator
    let microphoneManager = DependencyContainer.shared.microphoneManager
    
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"

    var body: some View {

        let activeThreat = coordinator.activeEvents.last(where: { $0.isRevealed })
        
        let statusText: String = {
            if let threatLabel = activeThreat?.threatLabel {
                return AppGlobals.localizeText(label: threatLabel).capitalized
            } else if microphoneManager.isListening {
                return String(localized: AppGlobals.listening)
            } else {
                return String(localized: AppGlobals.offline)
            }
        }()
        
        HStack(spacing: 8) {
            Circle()
                .fill(microphoneManager.isListening ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(LocalizedStringKey(statusText))
                .textCase(.uppercase)
                .font(.caption2.monospaced())
                .foregroundStyle(.green)
                .lineLimit(1)
                .animation(.none, value: statusText) // 🚨 Prevents "blurred" text during fast swaps
        }
        .environment(\.locale, Locale(identifier: preferredLanguage))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(ui.isMenuOpen ? 0.0 : 1.0)
    }
}
