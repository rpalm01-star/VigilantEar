import SwiftUI

struct StartupVerificationView: View {
    @Bindable var viewModel: StartupVerificationViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            headerSection
            
            // Fixed: No '$' prefix needed for ForEach with @Observable
            List(viewModel.steps) { step in
                VerificationRow(step: step)
            }
            .listStyle(.plain)
            .frame(maxHeight: 300)
            
            if !viewModel.isFinished {
                ProgressView("Running Diagnostics...")
                    .padding()
            }
        }
        .padding()
        .onAppear {
            Task {
                await viewModel.runDiagnostics()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("VigilantEar")
                .font(.largeTitle.bold())
            
            Text("Hardware & System Check")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }
}

struct VerificationRow: View {
    let step: VerificationTask
    
    var body: some View {
        HStack {
            Text(step.type.rawValue)
            Spacer()
            statusIcon
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
