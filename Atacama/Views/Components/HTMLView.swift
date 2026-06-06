//
//  HTMLView.swift
//  Atacama
//
//  Renders server-produced HTML (from POST /api/preview) in a WKWebView. Used only
//  to show a faithful preview — the app never reimplements AML rendering.
//

import SwiftUI
import WebKit

#if os(iOS)
struct HTMLView: UIViewRepresentable {
    let html: String
    /// Document base URL for resolving relative links/assets — the target server.
    var baseURL: String?

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrappedHTML, baseURL: baseURL.flatMap(URL.init(string:)))
    }

    private var wrappedHTML: String { wrapForPreview(html) }
}
#else
struct HTMLView: NSViewRepresentable {
    let html: String
    /// Document base URL for resolving relative links/assets — the target server.
    var baseURL: String?

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrappedHTML, baseURL: baseURL.flatMap(URL.init(string:)))
    }

    private var wrappedHTML: String { wrapForPreview(html) }
}
#endif

/// Wrap the fragment in a minimal responsive HTML document for legibility.
private func wrapForPreview(_ fragment: String) -> String {
    """
    <!doctype html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body { font: -apple-system-body; margin: 16px; line-height: 1.5; }
    </style>
    </head>
    <body>\(fragment)</body>
    </html>
    """
}
