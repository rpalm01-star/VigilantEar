import SwiftUI

struct CustomizationsView: View {
    @EnvironmentObject var ui: UIManager
    
    @State private var menuIdentity = UUID()
    
    private let menuFont = Font.system(size: 14, weight: .bold, design: .monospaced)

    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    originalMenuContent
                }
                .frame(maxWidth: .infinity)
            }
        }
        .id(menuIdentity)
        .frame(maxWidth: .infinity)
        .environment(\.locale, Locale(identifier: preferredLanguage))
        .onChange(of: ui.isMenuOpen) { _, isOpen in
            if isOpen {
                menuIdentity = UUID()
            }
        }
    }
    
    private var originalMenuContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AppTitleView()
                    .id("MenuTop")
                    .padding(.leading, -6)
                    .padding(.top, 8)
                    .padding(.bottom, 0)
                
                customHeader(AppGlobals.appPreferencesHeader)
                    .padding(.top, 8)
                
                // Customizations (Preferences) button — now proper NavigationLink
                NavigationLink(destination: PreferencesPanelView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 20))
                        Text(AppGlobals.customizations)
                            .foregroundColor(.green.opacity(0.75))
                        Spacer()
                    }
                }
                .modifier(LiquidGlassModifier())
                .disabled(DependencyContainer.shared.debugSimulationManager.isEmergencySimulationRunning)
                
                // Data Sources button — clean NavigationLink
                NavigationLink(destination: AlertSourcesPanelView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "globe.desk")
                            .font(.system(size: 20))
                        Text("Data Sources")
                            .foregroundColor(.green.opacity(0.75))
                        Spacer()
                    }
                }
                .modifier(LiquidGlassModifier())
                .disabled(DependencyContainer.shared.debugSimulationManager.isEmergencySimulationRunning)
                .padding(.top, 10)
                
                customHeader(AppGlobals.legalHeader)
                    .padding(.top, 8)
                
                VStack(spacing: 10) {
                    VStack(spacing: 10) {
                        legalGlassLink(title: AppGlobals.privacyPolicy, icon: "arrow.down.document", filename: "PRIVACY")
                        legalGlassLink(title: AppGlobals.termsOfService, icon: "hand.raised.fill", filename: "TERMS")
                        legalGlassLink(title: AppGlobals.support, icon: "arrow.down.document.fill", filename: "SUPPORT")
                        legalGlassLink(title: AppGlobals.appInfoReadMe, icon: "arrow.down.document", filename: "README")
                    }
                }
                
                customHeader(AppGlobals.simulatorsHeader)
                    .padding(.top, 8)
                
                Button(action: {
                    ThreatSimulator.runFireTruckDriveBy(
                        location: DependencyContainer.shared.microphoneManager.currentLocation,
                        heading: DependencyContainer.shared.microphoneManager.currentHeading,
                        coordinator: DependencyContainer.shared.acousticCoordinator
                    )
                    ui.isMenuOpen = false
                }) {
                    HStack(spacing: 4) {
                        Image("firemanHat")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text(AppGlobals.firetruckSimulator)
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                .modifier(LiquidGlassModifier())
                
                Button(action: {
                    if (!DependencyContainer.shared.debugSimulationManager.isEmergencySimulationRunning) {
                        DependencyContainer.shared.debugSimulationManager.handleDoubleTap()
                        ui.isMenuOpen = false
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .frame(width: 20, height: 20)
                        Text(AppGlobals.emergencyAlertsSimulator)
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                .modifier(LiquidGlassModifier())
                .disabled(DependencyContainer.shared.debugSimulationManager.isEmergencySimulationRunning)
                .padding(.top, 10)

                VStack(spacing: 6) {
                    Image("WingdingsLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                    
                    VStack(spacing: 0) {
                        Text(AppGlobals.wingdingsInc)
                        Text(AppGlobals.allRightsReserved)
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
    }
    
    private func customHeader(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(menuFont)
            .foregroundColor(.gray)
            .padding(.bottom, 12)
            .padding(.top, 10)
    }
    
    private func legalGlassLink(title: LocalizedStringResource, icon: String, filename: String, addLanguageSuffix: Bool = true) -> some View {
        let baseURL = "https://rpalm01-star.github.io/VigilantEar/"
        var langSuffix = preferredLanguage == "en" ? String.empty : "_\(preferredLanguage)"
        if (!addLanguageSuffix) { langSuffix = String.empty }
        let fullURL = "\(baseURL)\(filename)\(langSuffix).md"
        let url = URL(string: fullURL)!
        
        return NavigationLink(destination: LegalDocumentView(title: title, resourceName: url)) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                Text(title)
                Spacer()
            }
            .foregroundColor(.white)
        }
        .modifier(LiquidGlassModifier())
    }
}

struct LiquidGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
}
