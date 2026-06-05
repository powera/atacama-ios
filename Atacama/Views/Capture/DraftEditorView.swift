//
//  DraftEditorView.swift
//  Atacama
//
//  Editable draft body with a live dictation transcript appended below. Exposes the
//  current text selection so the capture screen can wrap it in a colortext footnote.
//
//  Text selection: a UITextView-backed editor is used so we can read the selected
//  range reliably across iOS versions (SwiftUI's TextEditor only exposes selection
//  on iOS 18+). The selected range is reported up via `selectedRange`.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct DraftEditorView: View {
    @Binding var text: String
    /// Live partial transcript from STT, shown faded below the committed text.
    let liveTranscript: String
    /// Reports the current selection (as a String range into `text`), or nil.
    @Binding var selectedRange: Range<String.Index>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if os(iOS)
            SelectableTextEditor(text: $text, selectedRange: $selectedRange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            TextEditor(text: $text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif

            if !liveTranscript.isEmpty {
                Text(liveTranscript)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.horizontal, 4)
            }
        }
    }
}

#if os(iOS)
/// A UITextView wrapper that surfaces the selected text range as a String index range.
private struct SelectableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: Range<String.Index>?

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: SelectableTextEditor

        init(_ parent: SelectableTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let selected = textView.selectedTextRange, !selected.isEmpty else {
                parent.selectedRange = nil
                return
            }
            let start = textView.offset(from: textView.beginningOfDocument, to: selected.start)
            let length = textView.offset(from: selected.start, to: selected.end)
            let text = textView.text ?? ""
            guard let lower = text.index(text.startIndex, offsetBy: start, limitedBy: text.endIndex),
                  let upper = text.index(lower, offsetBy: length, limitedBy: text.endIndex)
            else {
                parent.selectedRange = nil
                return
            }
            parent.selectedRange = lower ..< upper
        }
    }
}
#endif
