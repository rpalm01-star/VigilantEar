import SwiftUI

// MARK: - Editable wrapper
struct EditableSoundProfile: Identifiable {
    let id = UUID()
    let displayName: String
    let originalKeywords: [String]
    
    var category: ThreatCategory
    var minimumConfidence: Double
    var leadInTime: Double
    var tailMemory: Double
    var cooldown: Double
    var maxRange: Double
    var ceiling: Double
    var hapticCount: Int
    var shouldSnapToRoad: Bool
}

struct SoundProfilesPanelView: View {
    @Environment(\.dismiss) private var dismiss   // for the Done button
    
    @State private var profiles = SoundProfile.allEditableProfiles
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header row with Done button
                HStack {
                    Text(AppGlobals.soundProfiles)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                        .tracking(4)
                    
                    Spacer()
                    
                    Button(AppGlobals.done) {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.yellow)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.95))
                
                // Yellow divider line moved below the full header
                Rectangle()
                    .frame(height: 3)
                    .foregroundColor(.yellow.opacity(0.7))
                
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach($profiles) { $profile in
                            LCARSCardView(
                                title: profile.displayName,
                                keywords: profile.originalKeywords.joined(separator: ", "),
                                category: $profile.category,
                                minimumConfidence: $profile.minimumConfidence,
                                leadInTime: $profile.leadInTime,
                                tailMemory: $profile.tailMemory,
                                cooldown: $profile.cooldown,
                                maxRange: $profile.maxRange,
                                ceiling: $profile.ceiling,
                                hapticCount: $profile.hapticCount,
                                shouldSnapToRoad: $profile.shouldSnapToRoad
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(AppGlobals.soundProfiles)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - LCARS Card (unchanged from previous version)
struct LCARSCardView: View {
    let title: String
    let keywords: String
    @Binding var category: ThreatCategory
    @Binding var minimumConfidence: Double
    @Binding var leadInTime: Double
    @Binding var tailMemory: Double
    @Binding var cooldown: Double
    @Binding var maxRange: Double
    @Binding var ceiling: Double
    @Binding var hapticCount: Int
    @Binding var shouldSnapToRoad: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(.yellow)
                Spacer()
            }
            
            Text(keywords)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.yellow.opacity(0.7))
                .lineLimit(2)
                .truncationMode(.tail)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ThreatCategory.allCases, id: \.self) { cat in
                        Button(action: { category = cat }) {
                            Text(cat.rawValue.capitalized)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(category == cat ? .black : .yellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(category == cat ? Color.yellow : Color.clear)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                ParameterRow(title: "MIN CONFIDENCE", value: $minimumConfidence, format: "%.2f", range: 0...1)
                ParameterRow(title: "LEAD-IN TIME", value: $leadInTime, format: "%.1fs", range: 0...3)
                ParameterRow(title: "TAIL MEMORY", value: $tailMemory, format: "%.1fs", range: 0...5)
                ParameterRow(title: "COOLDOWN", value: $cooldown, format: "%.1fs", range: 0...5)
                ParameterRow(title: "MAX RANGE", value: $maxRange, format: "%.0f ft", range: 0...1500)
                ParameterRow(title: "CEILING", value: $ceiling, format: "%.2f", range: 0...1)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: "HAPTICS")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.8))
                        Spacer()
                        Text("\(hapticCount)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                    }
                    Slider(value: Binding(get: { Double(hapticCount) },
                                          set: { hapticCount = Int($0) }),
                           in: 0...5, step: 1)
                    .tint(.orange)
                }
                
                HStack {
                    Text(verbatim: "SNAP TO ROAD")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.8))
                    Spacer()
                    Toggle(String.empty, isOn: $shouldSnapToRoad)
                        .labelsHidden()
                        .tint(.orange)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.yellow.opacity(0.7), lineWidth: 2)
                .background(Color.black.opacity(0.85))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ParameterRow: View {
    let title: String
    @Binding var value: Double
    let format: String
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.8))
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
            }
            Slider(value: $value, in: range, step: 0.01)
                .tint(.orange)
        }
    }
}
