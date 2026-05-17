import SwiftUI
import MarkdownUI

// MARK: - Custom Theme Extension
extension Theme {
    static var vigilantTheme: Theme {
        // Start with the GitHub theme as a base
        Theme.gitHub
        // Overwrite its code block renderer
            .codeBlock { configuration in
                // Safely unwrap and clean the language string
                let lang = configuration.language ?? ""
                let cleanLang = lang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                if cleanLang == "mermaid" || configuration.content.contains("graph TD") {
                    
                    // 👇 INVOKING YOUR CUSTOM WKWEBVIEW HERE 👇
                    VStack {
                        MermaidWebView(mermaidCode: configuration.content)
                            .frame(minHeight: 350) // Bumped up slightly to ensure no SVG clipping
                            .padding(.vertical, 8)
                    }
                    .markdownMargin(top: 8, bottom: 16)
                    
                } else {
                    // Render standard code block for anything else
                    ScrollView(.horizontal) {
                        configuration.label
                            .relativeLineSpacing(.em(0.225))
                            .markdownTextStyle {
                                FontFamilyVariant(.monospaced)
                                FontSize(.em(0.85))
                            }
                            .padding(16)
                    }
                    .background(Color(white: 0.1)) // Dark grey background
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .markdownMargin(top: 0, bottom: 16)
                }
            }
    }
}

// MARK: - Legal Document View
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
                    // Apply your injected theme directly
                        .markdownTheme(.vigilantTheme)
                        .markdownTextStyle {
                            BackgroundColor(.black)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(light: .white, dark: Color(rgba: 0x1819_1dff)))
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.locale, Locale(identifier: preferredLanguage))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMarkdownFromGitHub()
        }
    }
    
    private func loadMarkdownFromGitHub() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: resourceName)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await MainActor.run {
                    self.loadFailed = true
                    self.isLoading = false
                }
                return
            }
            
            if let content = String(data: data, encoding: .utf8) {
                // Double sanitization sweep for invisible spaces and line breaks
                let sanitizedContent = content
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .replacingOccurrences(of: "\r\n", with: "\n")
                
                await MainActor.run {
                    self.markdownContent = sanitizedContent
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.loadFailed = true
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.loadFailed = true
                self.isLoading = false
            }
        }
    }
}
