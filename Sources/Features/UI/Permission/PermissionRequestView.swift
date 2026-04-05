import SwiftUI

struct PermissionRequestView: View {
    
    @Environment(\.dependencyContainer) private var dependencies
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "microphone.badge.plus")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("VigilantEar needs microphone access")
                .font(.title)
                .multilineTextAlignment(.center)
            
            Text("To detect loud vehicles and emergency sirens in real time.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Button("Grant Permissions") {
                print("Permission button tapped")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}
