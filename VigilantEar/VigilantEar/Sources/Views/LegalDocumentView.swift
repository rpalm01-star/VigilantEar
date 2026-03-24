import SwiftUI
import MarkdownUI

struct LegalDocumentView: View {
    let title: LocalizedStringResource
    let resourceName: URL
    
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    
    @State private var markdownContent: String = ""
    @State private var isLoading = true
    @State private var loadFailed = false
    
    var body: some View {
        Group {
            if loadFailed {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(AppGlobals.synchronizationFailed)
                        .font(.headline)
                }
            } else if isLoading {
                VStack(spacing: 16) {
                    ProgressView().tint(.accentColor)
                    Text(AppGlobals.loading)
                        .font(.caption.monospaced())
                }
            } else {
                ScrollView {
                    Markdown(markdownContent)
                        .markdownTheme(.gitHub)
                        .markdownTextStyle {
                            BackgroundColor(.black)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(light: .white, dark: Color(rgba: 0x1819_1dff)))   // ← your exact panel background
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.locale, Locale(identifier: preferredLanguage))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Updated to call the network function
            await loadMarkdownFromGitHub()
        }
    }
    
    private func loadMarkdownFromGitHub() async {
        do {
            // Fetch data directly from the network using async/await
            let (data, response) = try await URLSession.shared.data(from: resourceName)
            
            // Ensure we got a successful HTTP response (200 OK) so we don't accidentally display a 404 error page as markdown
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await MainActor.run {
                    self.loadFailed = true
                    self.isLoading = false
                }
                return
            }
            
            // Convert the raw data to a UTF-8 String
            if let content = String(data: data, encoding: .utf8) {
                await MainActor.run {
                    self.markdownContent = content
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.loadFailed = true
                    self.isLoading = false
                }
            }
        } catch {
            // Catch network errors (no internet, timeouts, etc.)
            await MainActor.run {
                self.loadFailed = true
                self.isLoading = false
            }
        }
    }
}
