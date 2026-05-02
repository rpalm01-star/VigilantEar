import SwiftUI

struct StartupVerificationView: View {
    @Bindable var viewModel: StartupVerificationViewModel
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
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
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
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
                    ForEach(Array(viewModel.steps.prefix(4))) { step in
                        VerificationRow(step: step)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Right Column (Remaining 3 items, sitting next to it)
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.steps.dropFirst(4))) { step in
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
        VStack(alignment: isLandscape ? .leading : .center, spacing: 4) {
            Text(AppGlobals.applicationTitle)
                .font(.system(size: 32, weight: .black, design: .monospaced))
            // 🚨 Double-stacked shadow for the true CRT radar glow
                .foregroundStyle(.green)
                .shadow(color: .green.opacity(0.8), radius: 6, x: 0, y: 0)
                .shadow(color: .green.opacity(0.3), radius: 15, x: 0, y: 0)
                .minimumScaleFactor(0.8)
            
            Text("SYSTEM INITIALIZATION")
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        }
    }
    
    private var actionSection: some View {
        Group {
            if !viewModel.isFinished {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.green)
                    Text("Verifying subsystems...")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                
            } else if viewModel.allPassed {
                Text("SYSTEMS ARE A GO!")
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
            } else {
                Button(action: { Task { await viewModel.runDiagnostics() } }) {
                    Label("RETRY SYSTEM CHECKS", systemImage: "arrow.clockwise")
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

// MARK: - Individual Row (Unchanged)
struct VerificationRow: View {
    let step: VerificationTask
    
    var body: some View {
        HStack(spacing: 12) {
            Text(step.type.rawValue)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            
            Spacer()
            
            if let reason = step.failureReason, step.status == .failed {
                Text(reason)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
            statusIcon
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.gray)
                .font(.system(size: 16))
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.cyan)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 16))
        }
    }
}
