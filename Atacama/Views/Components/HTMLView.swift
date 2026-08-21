//
//  HTMLView.swift
//  Atacama
//
//  Renders server-produced HTML — a POST /api/preview result while authoring, or a
//  post's body_html while reading — in a WKWebView. Used only to show a faithful
//  rendering: the app never reimplements AML.
//

import SwiftUI
import WebKit

#if os(iOS)
struct HTMLView: UIViewRepresentable {
    let html: String
    /// Document base URL for resolving relative links/assets — the target server.
    var baseURL: String?
    /// Absolute AML stylesheet URLs to link, in order. See `AMLStylesheet`.
    var stylesheetURLs: [String] = []

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrappedHTML, baseURL: baseURL.flatMap(URL.init(string:)))
    }

    private var wrappedHTML: String { wrapForPreview(html, stylesheetURLs: stylesheetURLs) }
}
#else
struct HTMLView: NSViewRepresentable {
    let html: String
    /// Document base URL for resolving relative links/assets — the target server.
    var baseURL: String?
    /// Absolute AML stylesheet URLs to link, in order. See `AMLStylesheet`.
    var stylesheetURLs: [String] = []

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrappedHTML, baseURL: baseURL.flatMap(URL.init(string:)))
    }

    private var wrappedHTML: String { wrapForPreview(html, stylesheetURLs: stylesheetURLs) }
}
#endif

/// Resolves where to load the reader's AML stylesheet from for a given server.
///
/// The stylesheet is what styles the colortext blocks, MLQs, literal spans
/// (`<< … >>`), inline titles and wiki links that newslettr's
/// `internal/aml/generator.go` emits. Without it the generated markup is bare
/// `<span>`s — a colortext sigil shows but not its box, and a literal span reads
/// as ordinary prose — which is exactly how a `<< … >>` post looked in the
/// reading detail view before this existed.
///
/// **Which path serves it differs per host, and only one is public on each.**
/// A reader-served content domain (earlyversion.com, blog.pow3.com, …) serves
/// `/reader/static/` anonymously. On the publisher (newslettr.com) that same
/// prefix is behind the author gate and 303s to the login page, so a client
/// asking there for CSS gets an HTML redirect and no styling at all; the
/// publisher's own public copy lives under `/publisher/static/` instead.
///
/// So the server names it: `styles.colortext` in `GET /api/atacama-config`.
/// Servers stored before that field existed report nothing, so both known paths
/// are linked as a fallback — the one that misses redirects to an HTML page,
/// which a browser will not apply as a stylesheet, leaving the other to win.
enum AMLStylesheet {
    static let readerPath = "/reader/static/css/colortext.css"
    static let publisherPath = "/publisher/static/css/colortext.css"

    /// Stylesheet URLs to link for `server`, most likely first.
    static func urls(for server: ServerConfig?) -> [String] {
        guard let server else { return [] }
        if let advertised = server.colortextCSSURL, !advertised.isEmpty {
            return [advertised]
        }
        let origin = server.baseURL.trimmingTrailingSlash()
        guard !origin.isEmpty else { return [] }
        return [origin + readerPath, origin + publisherPath]
    }
}

/// Wrap the fragment in a minimal responsive HTML document for legibility.
private func wrapForPreview(_ fragment: String, stylesheetURLs: [String]) -> String {
    let links = stylesheetURLs
        .map { #"<link rel="stylesheet" href="\#($0)">"# }
        .joined(separator: "\n")
    return """
    <!doctype html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    \(links)
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
