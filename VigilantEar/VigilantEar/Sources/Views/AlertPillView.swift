//
//  AlertPillView.swift
//  VigilantEar
//
//  Created by Robert Palmer on 5/5/26.
//N
import SwiftUI

struct AlertPillView: View {
    
    let capManager = DependencyContainer.shared.capAlertManager
    
    var body: some View {
        let rawAlert = capManager.nearbyAlerts.first?.event.uppercased() ?? ""
        let activeAlertText = rawAlert.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAlertActive = !activeAlertText.isEmpty
        
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
            
            Text(activeAlertText)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .multilineTextAlignment(.trailing) // Align text to the right for symmetry
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.red.opacity(0.7))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isAlertActive ? 1.0 : 0)
    }
}
