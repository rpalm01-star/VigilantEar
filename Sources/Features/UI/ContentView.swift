import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                Text("VIGILANT EAR")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                    .padding()
                
                RadarView(events: [])   // safe empty start
                
                Text("Microphone ready – make some noise")
                    .foregroundStyle(.green.opacity(0.7))
            }
        }
    }
}

#Preview {
    ContentView()
}
