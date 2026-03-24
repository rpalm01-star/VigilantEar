import SwiftUI

struct AlertSourcesPanelView: View {
    @EnvironmentObject var ui: UIManager
    
    // MARK: - Alert toggles – permanent local storage
    @AppStorage("alert_nws") private var nwsEnabled = true
    @AppStorage("alert_europe") private var europeEnabled = true
    @AppStorage("alert_china_cma_en") private var chinaCMAEnEnabled = true
    @AppStorage("alert_china_cma_zh") private var chinaCMAZhEnabled = true
    @AppStorage("alert_china_mem_zh") private var chinaMEMZhEnabled = true
    @AppStorage("shazam_enabled") private var shazamEnabled = true
    
    // MARK: - Language preference
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                Text("Weather Alert Sources")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                
                VStack(spacing: 8) {
                    sourceToggle("🇺🇸", "Nat'l Weather (NWS)", systemImage: "cloud.rain.fill", isOn: $nwsEnabled)
                    sourceToggle("🇪🇺", "Europe MeteoGate", systemImage: "globe.europe.africa.fill", isOn: $europeEnabled)
                    sourceToggle("🇨🇳", "China CMA (English)", systemImage: "globe.central.south.asia", isOn: $chinaCMAEnEnabled)
                    sourceToggle("🇨🇳", "China CMA (中文)", systemImage: "globe.central.south.asia.fill", isOn: $chinaCMAZhEnabled)
                    sourceToggle("🇨🇳", "China MEM (中文)", systemImage: "globe.central.south.asia", isOn: $chinaMEMZhEnabled)
                }
                .padding(.horizontal, 16)
                
                Divider().background(.white.opacity(0.2))
                
                Text("Other Sources")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                
                VStack(spacing: 8) {
                    sourceToggle("🌍", "SHAZAM", systemImage: "music.quarternote.3", isOn: $shazamEnabled)
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .environment(\.locale, Locale(identifier: preferredLanguage))
            .navigationTitle("Data Sources")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Reusable toggle row with flag emoji
    private func sourceToggle(_ flag: String, _ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Text(flag)
                    .font(.system(size: 28))
                Label(title, systemImage: systemImage)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 4)
        .disabled(true)   // ← TEMPORARILY DISABLED until we wire them up
    }
}
