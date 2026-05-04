import SwiftUI

struct NeuralTickerHUD: View {
    
    private let manager = DependencyContainer.shared.soundEventLabelManager
    
    @State private var feed: [TickerItem] = []
    @State private var lastAddedTime: [String: Date] = [:]
    
    struct TickerItem: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let confidence: Double
    }
    
    var body: some View {
        GeometryReader { geo in
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 7) {
                    Spacer()
                        .frame(height: AppGlobals.NeuralTicker.topOffset)
                    
                    ForEach(feed.prefix(AppGlobals.NeuralTicker.maxVisibleRows)) { item in
                        
                        Text(item.label.uppercased())
                            .font(.system(size: AppGlobals.NeuralTicker.fontSize, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan.opacity(AppGlobals.NeuralTicker.textOpacity))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                GeometryReader { textGeo in
                                    ZStack(alignment: .trailing) {
                                        // 🚀 OPTIMIZATION: Removed live blur (.ultraThinMaterial).
                                        // Static opacity looks great but costs zero GPU cycles to calculate.
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.black.opacity(0.6))
                                        
                                        // Confidence fill
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.cyan.opacity(0.20))
                                            .frame(width: textGeo.size.width * item.confidence)
                                    }
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                            .task {
                                // 🚀 OPTIMIZATION: Swift Concurrency prevents memory leaks from old timers
                                try? await Task.sleep(nanoseconds: UInt64(AppGlobals.NeuralTicker.ttl * 1_000_000_000))
                                
                                if !Task.isCancelled {
                                    withAnimation(.easeOut(duration: AppGlobals.NeuralTicker.fadeOutDuration)) {
                                        feed.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                    }
                    
                    Spacer()
                }
                .frame(height: geo.size.height * AppGlobals.NeuralTicker.heightMultiplier)
                .padding(.trailing, 2)
                // 🚀 OPTIMIZATION: Now that the blur is gone, this works perfectly to flatten the UI
                .drawingGroup()
            }
        }
        .task {
            // 🚀 OPTIMIZATION: Safe background cleanup loop
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 25_000_000_000) // 25 seconds
                    let cutoff = Date().addingTimeInterval(-90)
                    lastAddedTime = lastAddedTime.filter { $0.value > cutoff }
                }
            }
            
            // Stream listener
            for await newEvent in manager.newEvents() {
                pushToFeed(with: newEvent)
            }
        }
    }
    
    @MainActor
    private func pushToFeed(with event: SoundLabelEvent) {
        let fullLabel = event.rawMLSoundLabel
        
        let label: String
        if fullLabel.count > AppGlobals.NeuralTicker.truncationThreshold,
           let lastUnderscore = fullLabel.lastIndex(of: "_") {
            label = String(fullLabel[..<lastUnderscore])
        } else {
            label = fullLabel
        }
        
        if let existingIndex = feed.firstIndex(where: { $0.label == label }) {
            feed[existingIndex] = TickerItem(label: label, confidence: event.confidence)
            return
        }
        
        if let lastTime = lastAddedTime[label],
           Date().timeIntervalSince(lastTime) < AppGlobals.NeuralTicker.cooldown {
            return
        }
        
        lastAddedTime[label] = Date()
        
        withAnimation(.spring(
            response: AppGlobals.NeuralTicker.insertResponse,
            dampingFraction: AppGlobals.NeuralTicker.insertDamping
        )) {
            feed.insert(TickerItem(label: label, confidence: event.confidence), at: 0)
            if feed.count > AppGlobals.NeuralTicker.maxFeedSize {
                feed.removeLast()
            }
        }
    }
}
