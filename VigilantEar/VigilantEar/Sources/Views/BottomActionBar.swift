import SwiftUI

struct BottomActionBar: View {
    @EnvironmentObject var ui: UIManager
    
    var body: some View {
        HStack(spacing: 0) {
            // 1. NAV / RE-CENTER
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("SnapToUser"), object: nil)
            }) {
                Image(systemName: "location.fill")
                    .frame(width: 70, height: 50)
                    .foregroundColor(.blue)
            }
            
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: 0.5, height: 24)
            
            // 2. SETTINGS GEAR
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    ui.isMenuOpen.toggle()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .frame(width: 70, height: 50)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 8)
        .background {
            Capsule()
            // 🚨 THE TRANSPARENCY FIX:
            // We use a very light black tint over a thin material.
            // This allows text underneath to remain readable.
                .fill(Color.black.opacity(0.2))
                .background(.ultraThinMaterial.opacity(0.6))
                .environment(\.colorScheme, .dark)
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .inset(by: 0.5)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        // Lighten the shadow so it doesn't "dirty" the song title text below it
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
