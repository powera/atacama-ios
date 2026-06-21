//
//  ShareViewController.swift
//  AtacamaShareExtension
//
//  Principal class of the Share Extension (referenced by Info.plist's
//  NSExtensionPrincipalClass). It pulls the shared URL (and any page title) out
//  of the extension context, then presents the SwiftUI ShareComposeView to let
//  the user file the link. Completing or cancelling tears down the extension.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        extractSharedContent { [weak self] url, title in
            self?.present(url: url, title: title)
        }
    }

    /// Host the SwiftUI compose view once the shared URL has been resolved.
    private func present(url: String?, title: String) {
        let compose = ShareComposeView(
            sharedURL: url ?? "",
            initialTitle: title,
            onFinish: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: compose)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    // MARK: - Extraction

    /// Resolve the shared URL and a candidate title from the extension's input
    /// items. Prefers a `public.url` attachment; falls back to a URL found in
    /// shared plain text. The attributed content text becomes the title.
    private func extractSharedContent(completion: @escaping (String?, String) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let title = items.compactMap { $0.attributedContentText?.string }
            .first { !$0.isEmpty } ?? ""

        let providers = items.flatMap { $0.attachments ?? [] }

        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                let url = (value as? URL)?.absoluteString
                DispatchQueue.main.async { completion(url, title) }
            }
            return
        }

        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, _ in
                let url = (value as? String).flatMap(Self.firstURL(in:))
                DispatchQueue.main.async { completion(url, title) }
            }
            return
        }

        DispatchQueue.main.async { completion(nil, title) }
    }

    /// Extract the first http(s) URL embedded in a shared text snippet.
    private static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, url.scheme == "http" || url.scheme == "https" {
                return url.absoluteString
            }
        }
        return nil
    }

    // MARK: - Lifecycle

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "com.yevaud.atacama.share", code: 0))
    }
}
