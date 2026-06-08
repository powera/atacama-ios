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
    /// Reports the current selection as a character-offset range into `text`, or nil.
    /// Offsets (not `String.Index`) are used because the range is consumed against a
    /// different `String` instance, and indices aren't transferable between instances.
    @Binding var selectedRange: Range<Int>?
    /// Whether dictation is currently active (reflected in the keyboard accessory mic).
    var isRecording: Bool = false
    /// Toggle dictation from the keyboard accessory bar. Lets the author switch from
    /// typing back to voice without hunting for the mic beneath the keyboard.
    var onToggleDictation: (() -> Void)?
    /// Starts the footnote picker from the keyboard accessory before selection is lost.
    var onAddFootnote: (() -> Void)?
    /// Instructional empty-state text inside the editor.
    var placeholder = "Tap the mic and start talking. Use New section between sections."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                #if os(iOS)
                SelectableTextEditor(
                    text: $text,
                    selectedRange: $selectedRange,
                    isRecording: isRecording,
                    onToggleDictation: onToggleDictation,
                    onAddFootnote: onAddFootnote
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #else
                TextEditor(text: $text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif

                if text.isEmpty && liveTranscript.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 220, maxHeight: .infinity)

            if !liveTranscript.isEmpty {
                Text(liveTranscript)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.horizontal, 4)
            }
        }
        .frame(minHeight: 240, maxHeight: .infinity)
    }
}

#if os(iOS)
/// A UITextView wrapper that surfaces the selected text range as a String index range.
private struct SelectableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: Range<Int>?
    var isRecording: Bool = false
    var onToggleDictation: (() -> Void)?
    var onAddFootnote: (() -> Void)?

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
        private weak var footnoteButton: UIBarButtonItem?

        init(_ parent: SelectableTextEditor) {
            self.parent = parent
        }

        /// Builds the bar shown above the keyboard while hand-editing: a mic toggle,
        /// a footnote action that can use the active selection before it is cleared,
        /// and a Done button to dismiss.
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
            let footnote = UIBarButtonItem(
                image: UIImage(systemName: "character.bubble"),
                style: .plain,
                target: self,
                action: #selector(addFootnote)
            )
            footnote.accessibilityLabel = "Add footnote"
            footnote.isEnabled = false
            self.footnoteButton = footnote
            let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
            let done = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(dismissKeyboard)
            )
            bar.items = [mic, footnote, spacer, done]
            return bar
        }

        func updateAccessory(isRecording: Bool) {
            micButton?.image = UIImage(systemName: isRecording ? "stop.fill" : "mic.fill")
            micButton?.accessibilityLabel = isRecording ? "Stop dictation" : "Start dictation"
            footnoteButton?.isEnabled = parent.selectedRange != nil
        }

        @objc private func toggleDictation() {
            parent.onToggleDictation?()
        }

        @objc private func addFootnote() {
            parent.onAddFootnote?()
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
                footnoteButton?.isEnabled = false
                return
            }
            // UITextView positions are UTF-16 offsets; convert to Character offsets so the
            // reported range lines up with Swift String indexing in the draft body.
            let utf16Start = textView.offset(from: textView.beginningOfDocument, to: selected.start)
            let utf16End = textView.offset(from: textView.beginningOfDocument, to: selected.end)
            let text = textView.text ?? ""
            let utf16 = text.utf16
            guard let lowerUTF16 = utf16.index(utf16.startIndex, offsetBy: utf16Start, limitedBy: utf16.endIndex),
                  let upperUTF16 = utf16.index(utf16.startIndex, offsetBy: utf16End, limitedBy: utf16.endIndex),
                  let lower = lowerUTF16.samePosition(in: text),
                  let upper = upperUTF16.samePosition(in: text)
            else {
                parent.selectedRange = nil
                footnoteButton?.isEnabled = false
                return
            }
            let lowerOffset = text.distance(from: text.startIndex, to: lower)
            let upperOffset = text.distance(from: text.startIndex, to: upper)
            parent.selectedRange = lowerOffset ..< upperOffset
            footnoteButton?.isEnabled = true
        }
    }
}
#endif
