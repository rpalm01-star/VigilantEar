//
//  NeuralHUD.swift
//  VigilantEar
//
//  Created by Robert Palmer on 5/11/26.
//

import SwiftUI

struct NeuralHUD: View {
    
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    @EnvironmentObject var ui: UIManager
    
    @State private var feed: [TickerItem] = []
    @State private var lastAddedTime: [String: Date] = [:]
    
    private let maxFeedSize: Int = 10
    private let manager = DependencyContainer.shared.soundLabelEventManager
    
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
                    
                    ForEach(feed.prefix(maxFeedSize)) { item in
                        
                        Text(LocalizedStringKey(item.label))
                            .textCase(.uppercase)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.green, .opacity(AppGlobals.NeuralTicker.textOpacity))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                GeometryReader { textGeo in
                                    ZStack(alignment: .trailing) {
                                        // Original dynamic style for other languages
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.black.opacity(0.15))
                                        
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.cyan.opacity(0.25))
                                            .frame(width: textGeo.size.width * item.confidence)
                                    }
                                }
                            )
                            .environment(\.locale, Locale(identifier: preferredLanguage))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                            .task {
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
            }
        }
        .opacity(ui.isMenuOpen ? 0.0 : 1.0)
        .task {
            // Safe background cleanup loop
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 25_000_000_000) // 25 seconds
                    let cutoff = Date().addingTimeInterval(-90)
                    lastAddedTime = lastAddedTime.filter { $0.value > cutoff }
                }
            }
            
            // Stream listener
            for await newEvent in manager.newEvents() {
                await MainActor.run {
                    pushToFeed(with: newEvent)
                }
            }
        }
    }
    
    @MainActor
    private func pushToFeed(with event: SoundLabelEvent) {
        let label = event.rawMLSoundLabel
                
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
            if feed.count > maxFeedSize {
                feed.removeLast()
            }
        }
    }
}
