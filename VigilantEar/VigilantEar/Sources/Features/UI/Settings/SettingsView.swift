import SwiftUI

struct SettingsView: View {
    @AppStorage("isMockMode") private var isMockMode = false
    @AppStorage("showRawData") private var showRawData = false
    @AppStorage("logToCloud") private var logToCloud = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Research Tools")) {
                    Toggle("Enable Mock Generator", isOn: $isMockMode)
                    Toggle("Log to Google Cloud", isOn: $logToCloud)
                }
                
                Section(header: Text("Visualization")) {
                    Picker("Display Mode", selection: $showRawData) {
                        Text("Acoustic Radar").tag(false)
                        Text("Raw Event Log").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("Account")) {
                    Text("robert@wingdingssocial.com")
                        .foregroundStyle(.secondary)
                    Text("Project: vigilantear-research")
                        .font(.caption)
                }
            }
            .navigationTitle("VigilantEar Settings")
        }
    }
}
