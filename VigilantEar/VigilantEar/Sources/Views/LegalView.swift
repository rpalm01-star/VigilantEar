//
//  LegalView.swift
//  VigilantEar
//
//  Created by Robert Palmer on 5/1/26.
//

import SwiftUI

struct LegalView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                
                Spacer()
                
                Text(AppGlobals.applicationTitle)
                    .font(.system(.headline, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.black)
                    .background {
                        // Soft mint background glow (behind everything)
                        Text(AppGlobals.applicationTitle)
                            .font(.system(.headline, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(AppGlobals.darkGray.opacity(0.9))
                            .blur(radius: 10)
                    }
                    .overlay {
                        Text(AppGlobals.applicationTitle)
                            .font(.system(.headline, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(.green)
                            .blur(radius: 0.9)                   // ← tweak this for outline thickness
                    }
                
                Spacer()
                
                Text("Legal • Privacy • Terms")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Buttons
                VStack(spacing: 16) {
                    Button {
                        if let url = URL(string: "https://rpalm01-star.github.io/VigilantEar/PRIVACY.html") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Privacy Policy", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button {
                        if let url = URL(string: "https://rpalm01-star.github.io/VigilantEar/TERMS.html") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                Text("(Swipe from top to close this view.)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                VStack(spacing: 0) {
                    
                    Image("WingdingsLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 72)                    // ← smaller
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                    
                    Text("© 2026 Wingdings, Inc. All rights reserved.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                }
            }
        }
    }
}
