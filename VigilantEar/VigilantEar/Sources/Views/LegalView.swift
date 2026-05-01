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
            VStack(spacing: 24) {
                Spacer()
                
                Text("VigilantEar")
                    .font(.title2.bold())
                
                Text("Accessibility • Privacy • Safety")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
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
                
                Spacer()
                
                Text("© 2026 VigilantEar. All rights reserved.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("Legal")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
