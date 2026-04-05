import SwiftUI

struct ContentView: View {
    
    @Environment(\.dependencies) private var dependencies
    
    var body: some View {
        // Temporary safe version until we wire live events
        RadarView(events: [])
    }
}
