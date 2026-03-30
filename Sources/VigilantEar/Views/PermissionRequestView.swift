import SwiftUI

struct PermissionRequestView: View {
    // Injected from VigilantEarApp.swift
    var permissions: PermissionsManager
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)
            
            Text("VigilantEar Research")
                .font(.largeTitle.bold())
            
            Text("To monitor acoustic pollution and calculate directional vectors, we need access to your hardware.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 20) {
                PermissionRow(icon: "mic.fill", title: "Microphone", description: "Required for Doppler and TDOA analysis.")
                PermissionRow(icon: "location.fill", title: "Location", description: "Used to map noise events to Google Maps.")
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 15).fill(Color.gray.opacity(0.1)))

            Button(action: {
                Task {
                    await permissions.requestAllPermissions()
                }
            }) {
                Text("Enable Research Mode")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Capsule().fill(Color.blue))
            }
            .padding(.top)
        }
        .padding(30)
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 30)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline.bold())
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
