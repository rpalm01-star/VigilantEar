import SwiftUI

struct StartupVerificationView: View {
    @Bindable var viewModel: StartupVerificationViewModel
    
    var body: some View {
        // Landscape optimized side-by-side layout
        HStack(spacing: 32) {
            
            // MARK: - Left Panel: Branding & Status
            VStack(alignment: .leading, spacing: 16) {
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("VIGILANT EAR")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .green.opacity(0.6), radius: 8, x: 0, y: 0)
                    // Scale down slightly if the phone is smaller
                        .minimumScaleFactor(0.8)
                    
                    Text("SYSTEM INITIALIZATION")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
                
                // Pushes the action button to the bottom left corner
                Spacer()
                
                // MARK: - Actions
                Group {
                    if !viewModel.isFinished {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(.green)
                            Text("Booting subsystems...")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.green)
                        }
                        .frame(height: 50)
                        
                    } else if viewModel.allPassed {
                        Text("SYSTEMS NOMINAL")
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
                            Label("REBOOT DIAGNOSTICS", systemImage: "arrow.clockwise")
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
            // Lock the left panel to a comfortable width so the list doesn't squish it
            .frame(width: 300)
            .padding(.vertical, 20)
            
            // MARK: - Right Panel: Verification List
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(viewModel.steps) { step in
                        VerificationRow(step: step)
                    }
                }
                .padding(.vertical, 20)
                // Add a tiny bit of padding to the right so it doesn't hug the notch/island
                .padding(.trailing, 20)
            }
            .frame(maxWidth: .infinity) // Take up the rest of the screen
        }
        // Safe area padding ensures we don't clip into the Dynamic Island
        .padding(.horizontal, 40)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            Task { await viewModel.runDiagnostics() }
        }
    }
}

// MARK: - Individual Row (Unchanged from the Terminal UI upgrade)
struct VerificationRow: View {
    let step: VerificationTask
    
    var body: some View {
        HStack(spacing: 12) {
            Text(step.type.rawValue)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
            
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
