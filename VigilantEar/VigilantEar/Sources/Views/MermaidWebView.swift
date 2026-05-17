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
        body { 
            margin: 4px; 
            padding: 4px;
            display: flex; 
            justify-content: center; 
            /* anchor to top to prevent top-clipping */
            align-items: flex-start; 
            background-color: transparent; 
            color: white; 
            font-family: -apple-system, sans-serif; 
        }
        .mermaid { 
            width: 100%;
            display: flex; 
            justify-content: center; 
        }
        /* Force SVG to respect bounds while maintaining aspect ratio */
        .mermaid svg {
            max-width: 100% !important;
            height: auto !important;
        }
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
