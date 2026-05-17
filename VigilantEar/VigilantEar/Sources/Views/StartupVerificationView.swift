// StartupVerificationView.swift
// VigilantEar
//
// Created by Robert Palmer on 5/9/26.
//

import SwiftUI

struct StartupVerificationView: View {
    @Bindable var viewModel: StartupVerificationViewModel
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // 🚨 ADD THIS: Sync with the language set in your menu
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    var isLandscape: Bool {
        verticalSizeClass == .compact
    }
    
    var body: some View {
        Group {
            if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        // 🚨 ADD THIS: Tell this view which language to use
        .environment(\.locale, Locale(identifier: preferredLanguage))
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            Task { await viewModel.runDiagnostics() }
        }
        // 🚨 ADD THIS: Instantly clear the warning when the user rotates the device
        .onChange(of: isLandscape) { _, newValue in
            viewModel.updateOrientationStatus(isLandscape: newValue)
            Task { await viewModel.runDiagnostics() }
        }
    }
    
    // MARK: - PORTRAIT LAYOUT
    private var portraitLayout: some View {
        VStack(spacing: 24) {
            header
                .padding(.top, 40)
            
            // ScrollView kept only for portrait just in case on smaller phones
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(viewModel.steps) { step in
                        VerificationRow(step: step)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            actionSection
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - LANDSCAPE LAYOUT
    private var landscapeLayout: some View {
        VStack(spacing: 20) {
            
            // 1. Header locked to the top left
            HStack {
                header
                Spacer()
            }
            
            // 2. The 2-Column Grid for the Checklist
            HStack(alignment: .top, spacing: 24) {
                
                // Left Column (First 4 items, safely directly under the header)
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.steps.prefix(3))) { step in
                        VerificationRow(step: step)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Right Column (Remaining 3 items, sitting next to it)
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.steps.dropFirst(3))) { step in
                        VerificationRow(step: step)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            Spacer(minLength: 10)
            
            // 3. Centered Action Button under everything
            actionSection
                .frame(maxWidth: 400) // Caps the width so it doesn't stretch comically wide
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
    }
    
    // MARK: - REUSABLE UI COMPONENTS
    
    private var header: some View {
        VStack(alignment: isLandscape ? .leading : .center, spacing: 2) {
            
            VStack(alignment: .center, spacing: 2) {
                
                HStack() {
                    Text(AppGlobals.appTitle)
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundStyle(.green)
                        .shadow(color: .green.opacity(0.8), radius: 6, x: 0, y: 0)
                        .shadow(color: .green.opacity(0.3), radius: 15, x: 0, y: 0)
                        .minimumScaleFactor(0.8)
                    
                    Text(verbatim: AppGlobals.appVersion)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.15))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                        )
                }
                .frame(minHeight: 36, maxHeight: 36)
            }
            
            Text(AppGlobals.systemInitialization)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        }
    }
    
    private var actionSection: some View {
        Group {
            if viewModel.allPassed {
                Text(AppGlobals.systemsAreAGo)
                    .font(.headline.monospaced())
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green.opacity(0.5), lineWidth: 1)
                    )
            } else if !viewModel.isFinished {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.green)
                    Text(AppGlobals.verifyingSubsystems)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            } else {
                Button(action: { Task { await viewModel.runDiagnostics() } }) {
                    Label(AppGlobals.retrySystemChecks, systemImage: "arrow.clockwise")
                        .font(.headline.monospaced())
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.orange.opacity(0.6), lineWidth: 1)
                        )
                }
            }
        }
    }
}

// MARK: - Individual Row (Updated)
struct VerificationRow: View {
    let step: VerificationTask
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            statusIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text(step.type.rawValue)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        step.status == .failed ? .red.opacity(0.9) : .green.opacity(0.75)
                    )
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                if let reason = step.failureReason, step.status == .failed {
                    Text(reason)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.9))
                        .minimumScaleFactor(0.8)
                        .lineLimit(nil)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var borderColor: Color {
        switch step.status {
        case .failed: return .red.opacity(0.6)
        case .passed: return .green.opacity(0.4)
        case .running: return .cyan.opacity(0.4)
        default: return .white.opacity(0.1)
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .pending, .notDetermined:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.gray)
                .font(.system(size: 22))
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.cyan)
                .frame(width: 22, height: 22)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 22))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 22))
        }
    }
}
