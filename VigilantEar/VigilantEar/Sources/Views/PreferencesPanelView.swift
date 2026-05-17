import SwiftUI

struct PreferencesPanelView: View {
    @EnvironmentObject var ui: UIManager
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Master Push Notifications Toggle (pure user preference)
    @AppStorage("pushNotificationsMasterEnabled") private var pushNotificationsMasterEnabled = false
    @State private var showSettingsLink = false
    
    // MARK: - Alert toggles – default to OFF
    @AppStorage("alert_nws") private var nwsEnabled = false
    @AppStorage("alert_knock") private var knockEnabled = false
    @AppStorage("alert_person") private var personEnabled = false
    @AppStorage("alert_alarm") private var alarmEnabled = false
    @AppStorage("alert_siren") private var sirenEnabled = false
    
    // MARK: - Language preference
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Language picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Language")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                    
                    Picker("Language", selection: $preferredLanguage) {
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Español").tag("es")
                        Text(verbatim: "中文").tag("zh-Hans")
                        Text(verbatim: "Français").tag("fr")
                        Text(verbatim: "Deutsch").tag("de")
                        Text(verbatim: "日本語").tag("ja")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                }

                Divider().background(.white.opacity(0.2))

                // MARK: - Master Toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Allow Push Notifications", isOn: $pushNotificationsMasterEnabled)
                        .toggleStyle(.switch)
                        .padding(.vertical, 4)
                    
                    if showSettingsLink {
                        Button(action: openAppSettings) {
                            Text("Notifications disabled — Open Settings")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                Divider().background(.white.opacity(0.2))
                
                // MARK: - Sub-toggles (greyed out when master is OFF)
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppGlobals.alertPreferences)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 0)
                    
                    Toggle(AppGlobals.alarms, isOn: $alarmEnabled)
                        .disabled(!pushNotificationsMasterEnabled)
                    Toggle(AppGlobals.doorbells, isOn: $knockEnabled)
                        .disabled(!pushNotificationsMasterEnabled)
                    Toggle(AppGlobals.peopleCloseby, isOn: $personEnabled)
                        .disabled(!pushNotificationsMasterEnabled)
                    Toggle(AppGlobals.severeWeather, isOn: $nwsEnabled)
                        .disabled(!pushNotificationsMasterEnabled)
                    Toggle(AppGlobals.sirens, isOn: $sirenEnabled)
                        .disabled(!pushNotificationsMasterEnabled)
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .environment(\.locale, Locale(identifier: preferredLanguage))
            .navigationTitle(AppGlobals.alertPreferences)
            .navigationBarTitleDisplayMode(.inline)
            
            // MARK: - Logic
            .onChange(of: pushNotificationsMasterEnabled) { _, newValue in
                handleMasterToggleChange(newValue)
            }
            .onAppear {
                Task { await refreshNotificationStatus() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await refreshNotificationStatus() }
                }
            }
        }
    }
    
    private func refreshNotificationStatus() async {
        let (status, _) = await checkNotificationStatusOnly()
        showSettingsLink = (status == .failed)
        // IMPORTANT: Do NOT force master toggle back to true
    }
    
    private func handleMasterToggleChange(_ newValue: Bool) {
        if newValue {
            Task {
                let (status, _) = await checkNotificationStatusOnly()
                
                if status == .passed {
                    enableAllSubToggles()
                    showSettingsLink = false
                } else if status == .failed {
                    pushNotificationsMasterEnabled = false
                    showSettingsLink = true
                } else {
                    // .notDetermined → request permission now
                    let (grantedStatus, _) = await requestNotificationPermission()
                    if grantedStatus == .passed {
                        enableAllSubToggles()
                        showSettingsLink = false
                    } else {
                        pushNotificationsMasterEnabled = false
                        showSettingsLink = true
                    }
                }
            }
        } else {
            showSettingsLink = false
        }
    }
    
    private func enableAllSubToggles() {
        alarmEnabled = true
        knockEnabled = true
        personEnabled = true
        nwsEnabled = true
        sirenEnabled = true
    }
    
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    
    // Pure status check (never requests permission)
    private func checkNotificationStatusOnly() async -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return (.passed, nil)
        case .denied:
            return (.failed, AppGlobals.notificationsDisabled)
        case .notDetermined:
            return (.notDetermined, nil)
        @unknown default:
            return (.failed, AppGlobals.notificationStatusUnknown)
        }
    }
    
    // Only called when user flips master ON
    private func requestNotificationPermission() async -> (status: VerificationStatus, reason: LocalizedStringResource?) {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            return granted ? (.passed, nil) : (.failed, AppGlobals.notificationPermissionRequired)
        } catch {
            return (.failed, AppGlobals.notificationPermissionRequired)
        }
    }
}