//
//  AppTitleView.swift
//  VigilantEar
//
//  Created by Robert Palmer on 5/5/26.
//


import SwiftUI

struct AppTitleView: View {
    var body: some View {
        Text(AppGlobals.appTitle)
            .font(.system(.headline, design: .monospaced))
            .tracking(3)
            .foregroundStyle(.black)
            // 1. The "Cute" Shadow Layer
            .background {
                Text(AppGlobals.appTitle)
                    .font(.system(.headline, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(AppGlobals.darkGray.opacity(0.9))
                    .blur(radius: 10)
            }
            // 2. The Neon Glow Layer
            .overlay {
                Text(AppGlobals.appTitle)
                    .font(.system(.headline, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.green)
                    .blur(radius: 0.9)
            }
            // Ensure the glow doesn't get clipped by the frame
            .padding(.horizontal, 4)
            .drawingGroup(opaque: false)
    }
}
