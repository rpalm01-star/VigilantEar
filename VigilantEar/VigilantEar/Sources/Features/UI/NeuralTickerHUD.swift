import SwiftUI

/// A vertical, real-time ticker that displays the most recent raw ML sound labels
/// detected by the SoundLabelEventManager.
///
/// ## Features
/// - **Positioning**: Far-right justified, positioned below the "VIGILANT EAR" title
///   and above the Telemetry panel.
/// - **Display Limit**: Shows a maximum of `maxVisibleRows` entries.
/// - **TTL (Time To Live)**: Each label remains visible for `ttl` seconds before auto-removing.
/// - **Cooldown**: `cooldown` seconds prevents the same label from being re-added after
///   it times out, reducing visual spam from repeated detections.
/// - **Duplicate Prevention**: If a label is already visible in the queue, its TTL is
///   refreshed instead of creating a duplicate entry (no "pop" animation).
/// - **Label Truncation**: Labels longer than `truncationThreshold` characters are
///   truncated after the last underscore (e.g., `glass_break_02` → `glass_break`).
///
/// ## Configuration
/// All timing, layout, and behavior values are defined in `AppGlobals.NeuralTicker`.
struct NeuralTickerHUD: View {
    
    /// Shared manager that streams raw ML sound classification events
    private let manager = DependencyContainer.shared.soundEventLabelManager
    
    /// Currently visible ticker items (newest at index 0)
    @State private var feed: [TickerItem] = []
    
    /// Tracks the last time each label was added/refreshed (used for cooldown enforcement)
    @State private var lastAddedTime: [String: Date] = [:]
    
    /// A single ticker entry. Uses a fresh UUID on each insert so the TTL timer
    /// can be reset when refreshing an existing label.
    struct TickerItem: Identifiable, Equatable {
        let id = UUID()
        let label: String
    }
    
    var body: some View {
        GeometryReader { geo in
            HStack {
                Spacer()  // Pushes the entire ticker to the far right edge
                
                VStack(alignment: .trailing, spacing: 7) {
                    
                    // Offset below the "VIGILANT EAR" title
                    Spacer()
                        .frame(height: AppGlobals.NeuralTicker.topOffset)
                    
                    // Display only the top N entries
                    ForEach(feed.prefix(AppGlobals.NeuralTicker.maxVisibleRows)) { item in
                        Text(item.label.uppercased())
                            .font(.system(size: AppGlobals.NeuralTicker.fontSize, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan.opacity(AppGlobals.NeuralTicker.textOpacity))
                            .padding(.horizontal, 1)
                            .padding(.vertical, 1)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                            .onAppear {
                                // Auto-remove after TTL expires
                                DispatchQueue.main.asyncAfter(deadline: .now() + AppGlobals.NeuralTicker.ttl) {
                                    withAnimation(.easeOut(duration: AppGlobals.NeuralTicker.fadeOutDuration)) {
                                        feed.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                    }
                    
                    Spacer()  // Keeps the ticker above the Telemetry panel
                }
                .frame(height: geo.size.height * AppGlobals.NeuralTicker.heightMultiplier)
                .padding(.trailing, 2)
            }
        }
        .task {
            // Periodic cleanup of stale cooldown timestamps
            Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { _ in
                let cutoff = Date().addingTimeInterval(-90)
                lastAddedTime = lastAddedTime.filter { $0.value > cutoff }
            }
            
            // Subscribe to raw ML labels from the manager
            for await newEvent in manager.newEvents() {
                await MainActor.run {
                    pushToFeed(with: newEvent)
                }
            }
        }
    }
    
    /// Processes an incoming raw ML label and decides whether to add, refresh, or ignore it.
    ///
    /// Logic order:
    /// 1. Truncate long labels (if > `truncationThreshold`) after the last underscore
    /// 2. If label already exists in queue → refresh its TTL (no duplicate entry)
    /// 3. Enforce cooldown (prevents re-addition after timeout)
    /// 4. Insert at top with animation, respecting `maxFeedSize`
    private func pushToFeed(with event: SoundLabelEvent) {
        let fullLabel = event.rawMLSoundLabel
        
        // Truncate only if longer than the configured threshold
        let label: String
        if fullLabel.count > AppGlobals.NeuralTicker.truncationThreshold,
           let lastUnderscore = fullLabel.lastIndex(of: "_") {
            label = String(fullLabel[..<lastUnderscore])
        } else {
            label = fullLabel
        }
        
        // Duplicate prevention: refresh TTL instead of adding a second copy
        if let existingIndex = feed.firstIndex(where: { $0.label == label }) {
            feed[existingIndex] = TickerItem(label: label)  // new UUID resets the TTL timer
            return
        }
        
        // Cooldown guard
        if let lastTime = lastAddedTime[label],
           Date().timeIntervalSince(lastTime) < AppGlobals.NeuralTicker.cooldown {
            return
        }
        
        lastAddedTime[label] = Date()
        
        withAnimation(.spring(
            response: AppGlobals.NeuralTicker.insertResponse,
            dampingFraction: AppGlobals.NeuralTicker.insertDamping
        )) {
            feed.insert(TickerItem(label: label), at: 0)
            if feed.count > AppGlobals.NeuralTicker.maxFeedSize {
                feed.removeLast()
            }
        }
    }
}
