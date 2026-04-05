import SwiftUI

struct ContentView: View {
    @Environment(\.dependencyContainer) private var dependencies
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("VIGILANT EAR")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.green)
                
                RadarView(events: [])   // safe for now
                
                Text("Microphone ready – make some noise")
                    .foregroundStyle(.green.opacity(0.7))
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.dependencyContainer, DependencyContainer.shared)
}
