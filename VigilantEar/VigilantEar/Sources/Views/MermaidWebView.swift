//
//  MermaidWebView.swift
//  VigilantEar
//
//  Created by Robert Palmer on 5/16/26.
//


import SwiftUI
import WebKit

struct MermaidWebView: UIViewRepresentable {
    let mermaidCode: String
    
    func makeUIView(context: Context) -> WKWebView {
        // 1. Initialize with minimal configuration
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // 2. Prevent the webview from aggressively caching or holding background state
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // 3. Inject the raw Mermaid code into a clean HTML template
        // Using the official Mermaid CDN ensures we get the latest stable renderer
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
            <script>
                mermaid.initialize({ startOnLoad: true, theme: 'dark' });
            </script>
            <style>
                body { margin: 0; display: flex; justify-content: center; align-items: center; height: 100vh; background-color: transparent; color: white; font-family: -apple-system, sans-serif; }
                .mermaid { display: flex; justify-content: center; }
            </style>
        </head>
        <body>
            <div class="mermaid">
                \(mermaidCode)
            </div>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    // 4. THE KILL SWITCH: This guarantees the memory is freed when SwiftUI destroys the view
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.stopLoading()
        uiView.loadHTMLString("", baseURL: nil)
        uiView.removeFromSuperview()
    }
}