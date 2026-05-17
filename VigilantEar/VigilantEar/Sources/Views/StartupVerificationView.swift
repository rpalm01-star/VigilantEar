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
                        VerificationRow(task: step)
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
        VStack(spacing: 12) {
            
            // 1. Header locked to the top left
            HStack {
                header
                Spacer()
            }
            
            // 2. The 2-Column Grid for the Checklist
            HStack(alignment: .top, spacing: 12) {
                
                // Left Column (First X items, safely directly under the header)
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.steps.prefix(2))) { step in
                        VerificationRow(task: step)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Right Column (Remaining X items, sitting next to it)
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.steps.dropFirst(2))) { step in
                        VerificationRow(task: step)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            Spacer(minLength: 10)
            
            // 3. Centered Action Button under everything
            actionSection
                .frame(maxWidth: 400) // Caps the width so it doesn't stretch comically wide
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 40)
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

struct VerificationRow: View {
    let task: VerificationTask
    
    var body: some View {
        // If it's a permission failure, make the whole row a button
        if task.status == .failed && task.isPermissionRelated {
            Button(action: openSettings) {
                rowContent
            }
            .buttonStyle(.plain) // Keeps it from looking like a standard blue link
        } else {
            // Otherwise, just render the normal, non-clickable row
            rowContent
        }
    }
    
    // MARK: - Visual Content
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 16) {
            // Your Status Icon (Checkmark, Error, Spinner, etc.)
            statusIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.type.rawValue)
                    .font(.subheadline)
                    .foregroundColor(task.status == .failed ? .red : .primary)
                
                if let reason = task.failureReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                }
            }
            Spacer()
        }
        .padding()
        // Optional: Add a subtle background to indicate it's tappable
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(task.status == .failed && task.isPermissionRelated ? Color.red.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(task.status == .failed ? Color.red : Color.green.opacity(0.5), lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    // MARK: - Helper Views
    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .running:
            ProgressView()
        case .pending, .notDetermined:
            Image(systemName: "circle.dashed").foregroundColor(.gray)
        }
    }
}
