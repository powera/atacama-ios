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
    /// Origin to load the reader's colortext stylesheet from. See `stylesheetURL`.
    var styleOrigin: String?

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrappedHTML, baseURL: baseURL.flatMap(URL.init(string:)))
    }

    private var wrappedHTML: String { wrapForPreview(html, styleOrigin: styleOrigin) }
}
#else
struct HTMLView: NSViewRepresentable {
    let html: String
    /// Document base URL for resolving relative links/assets — the target server.
    var baseURL: String?
    /// Origin to load the reader's colortext stylesheet from. See `stylesheetURL`.
    var styleOrigin: String?

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrappedHTML, baseURL: baseURL.flatMap(URL.init(string:)))
    }

    private var wrappedHTML: String { wrapForPreview(html, styleOrigin: styleOrigin) }
}
#endif

/// The reader's AML stylesheet, which styles the colortext blocks, MLQs, literal
/// text and wiki links that `internal/aml/generator.go` emits. Without it the
/// generated markup is bare `<span>`s: the sigil emoji shows, but the box,
/// colour and border that delimit a colortext footnote do not.
///
/// It must be loaded from a **content domain** (earlyversion.com and the other
/// reader-served sites), not from the authoring host. Reader and publisher are
/// separate services; newslettr.com is fronted by the publisher, whose auth gate
/// exempts only `/publisher/static/`, so this path 303s to the login page there.
private let stylesheetPath = "/reader/static/css/colortext.css"

/// Wrap the fragment in a minimal responsive HTML document for legibility.
///
/// `styleOrigin` is the origin to pull the reader stylesheet from; when nil the
/// document is still readable, just unstyled beyond the base rules below.
private func wrapForPreview(_ fragment: String, styleOrigin: String?) -> String {
    let link = styleOrigin.map {
        #"<link rel="stylesheet" href="\#($0.trimmingTrailingSlash())\#(stylesheetPath)">"#
    } ?? ""
    return """
    <!doctype html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    \(link)
    <style>
      body { font: -apple-system-body; margin: 16px; line-height: 1.5; }
      /* The theme variables colortext.css references live in the reader's
         main.css, which the preview does not load. Define the handful the
         colortext rules actually use so borders and code backgrounds resolve. */
      :root {
        --bg: #fafaf8; --bg-card: #ffffff; --bg-code: #f0ede8;
        --text: #1a1a1a; --text-muted: #777777; --text-dimmer: #aaaaaa;
        --border: #e0ddd8; --accent: #1a6b3c;
      }
      /* On the site a colortext body is a footnote: collapsed until the sigil
         is clicked. Proofing wants the opposite — the author is checking what
         they just dictated, so open every body by default. The sigil still
         toggles (see below) to check the reader's collapsed view. */
      .colortext-content { display: inline; }
      .colortext-content.collapsed { display: none; }
    </style>
    </head>
    <body>\(fragment)
    <script>
      // Tap-to-toggle, default open. The reader's main.js does the inverse
      // (adding .expanded); it is not loaded here, so this drives .collapsed.
      document.addEventListener('click', function (e) {
        var sigil = e.target.closest('.sigil');
        if (!sigil) return;
        var body = sigil.parentElement.querySelector('.colortext-content');
        if (body) body.classList.toggle('collapsed');
      });
    </script>
    </body>
    </html>
    """
}

private extension String {
    /// Trim a trailing slash so the origin and the stylesheet path join cleanly.
    func trimmingTrailingSlash() -> String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
