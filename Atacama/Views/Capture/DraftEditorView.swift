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
    /// Whether dictation is currently active (reflected in the keyboard accessory mic).
    var isRecording: Bool = false
    /// Toggle dictation from the keyboard accessory bar. Lets the author switch from
    /// typing back to voice without hunting for the mic beneath the keyboard.
    var onToggleDictation: (() -> Void)?
    /// Instructional empty-state text inside the editor.
    var placeholder = "Type or dictate. Select text, then Tools > Hide selected text for a colortext note."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                #if os(iOS)
                SelectableTextEditor(
                    text: $text,
                    selectedRange: $selectedRange,
                    isRecording: isRecording,
                    onToggleDictation: onToggleDictation
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #else
                TextEditor(text: $text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif

                if text.isEmpty && liveTranscript.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

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
    var isRecording: Bool = false
    var onToggleDictation: (() -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        // Drag-to-dismiss keeps voice-first ergonomics: the keyboard is only up while
        // hand-correcting, and a swipe puts it away.
        view.keyboardDismissMode = .interactive
        if onToggleDictation != nil {
            view.inputAccessoryView = context.coordinator.makeAccessoryView()
        }
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        context.coordinator.updateAccessory(isRecording: isRecording)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: SelectableTextEditor
        private weak var micButton: UIBarButtonItem?

        init(_ parent: SelectableTextEditor) {
            self.parent = parent
        }

        /// Builds the bar shown above the keyboard while hand-editing: a mic toggle so
        /// the author can hop back to voice, and a Done button to dismiss.
        func makeAccessoryView() -> UIToolbar {
            let bar = UIToolbar()
            bar.sizeToFit()
            let mic = UIBarButtonItem(
                image: UIImage(systemName: "mic.fill"),
                style: .plain,
                target: self,
                action: #selector(toggleDictation)
            )
            mic.accessibilityLabel = "Start dictation"
            self.micButton = mic
            let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
            let done = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(dismissKeyboard)
            )
            bar.items = [mic, spacer, done]
            return bar
        }

        func updateAccessory(isRecording: Bool) {
            micButton?.image = UIImage(systemName: isRecording ? "stop.fill" : "mic.fill")
            micButton?.accessibilityLabel = isRecording ? "Stop dictation" : "Start dictation"
        }

        @objc private func toggleDictation() {
            parent.onToggleDictation?()
        }

        @objc private func dismissKeyboard() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
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
