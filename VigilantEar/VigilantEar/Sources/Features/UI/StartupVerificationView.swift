import SwiftUI

struct StartupVerificationView: View {
    @Bindable var viewModel: StartupVerificationViewModel
    
    var body: some View {
        HStack(spacing: 40) {
            
            // Left Side: Branding / Instructions
            VStack(alignment: .leading, spacing: 16) {
                
                Text("VIGILANT EAR")
                    .font(.largeTitle.monospaced().bold())
                
                Text("Pre-flight Check")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if !viewModel.isFinished {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(.green)
                        Text("Initializing arrays...")
                            .font(.caption.monospaced())
                            .foregroundStyle(.green)
                    }
                } else if viewModel.allPassed {
                    Text("READY!")
                        .font(.headline.monospaced())
                        .foregroundStyle(.green)
                } else {
                    Button(action: { Task { await viewModel.runDiagnostics() } }) {
                        Label("RETRY SETUP CHECKS", systemImage: "arrow.clockwise")
                            .font(.caption.bold().monospaced())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.vertical, 20)
            
            // Right Side: The "Squished" Button List
            VStack(spacing: 8) {
                ForEach(viewModel.steps) { step in
                    VerificationRow(step: step)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(30)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            Task { await viewModel.runDiagnostics() }
        }
    }
}

struct VerificationRow: View {
    let step: VerificationTask
    
    var body: some View {
        HStack(spacing: 12) {
            Text(step.type.rawValue)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
            
            Spacer()
            
            if let reason = step.failureReason, step.status == .failed {
                Text(reason)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
            statusIcon
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.1))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var borderColor: Color {
        switch step.status {
        case .failed: return .red.opacity(0.5)
        case .passed: return .green.opacity(0.3)
        default: return .clear
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.gray)
                .font(.system(size: 14))
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.green)
        case .passed:
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "xmark.square.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))
        }
    }
}
