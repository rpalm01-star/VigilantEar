import SwiftUI

struct StartupVerificationView: View {
    @State private var viewModel = StartupVerificationViewModel()
    
    // Closure to notify the app coordinator to transition to the main app (e.g., RadarView)
    var onVerificationSuccess: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    Text("System Verification")
                        .font(.title2.bold())
                    Text("VigilantEar is checking hardware capabilities.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 32)
                
                // Interactive Diagnostic List
                List {
                    ForEach($viewModel.steps) { $step in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(step.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                
                                if case .failed(let reason) = step.status {
                                    Text("Error: \(reason)")
                                        .font(.footnote.bold())
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        } label: {
                            HStack {
                                statusIcon(for: step.status)
                                    .frame(width: 30)
                                
                                Text(step.title)
                                    .font(.body)
                                    .foregroundStyle(step.status == .pending ? .secondary : .primary)
                                
                                Spacer()
                            }
                        }
                        .tint(.primary) // Color of the expansion chevron
                    }
                }
                .listStyle(.insetGrouped)
                
                // Footer Action
                if viewModel.isVerificationComplete {
                    Button(action: {
                        if viewModel.allPassed {
                            onVerificationSuccess()
                        } else {
                            // Retry logic
                            Task { await viewModel.runDiagnostics() }
                        }
                    }) {
                        Text(viewModel.allPassed ? "Launch App" : "Retry Diagnostics")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.allPassed ? Color.green : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Color(.systemGroupedBackground))
            .task {
                await viewModel.runDiagnostics()
            }
        }
    }
    
    // Helper to render the correct icon based on state
    @ViewBuilder
    private func statusIcon(for status: DiagnosticStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }
}