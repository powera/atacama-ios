//
//  CaptureView.swift
//  Atacama
//
//  The primary authoring screen: dictate a stream-of-consciousness draft, edit it,
//  add colortext footnotes to selected text, pick a channel, preview, and submit.
//

import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var store = DraftStore.shared
    @StateObject private var stt = STTService()
    @StateObject private var tts = TTSService()

    @State private var selectedRange: Range<String.Index>?
    @State private var showColorPicker = false
    @State private var showPreview = false
    @State private var previewHTML: String?
    @State private var showMicPermissionAlert = false
    @State private var submittedURL: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Subject", text: $store.draft.subject)
                    .font(.headline)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                DraftEditorView(
                    text: $store.draft.body,
                    liveTranscript: stt.transcript,
                    selectedRange: $selectedRange
                )
                .padding(.horizontal)

                ChannelPicker(channels: store.channels, selection: $store.draft.channel)
                    .padding(.horizontal)

                controlBar
            }
            .navigationTitle("New post")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Read draft aloud", systemImage: "speaker.wave.2") {
                            tts.speak(store.draft.body)
                        }
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            session.signOut()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showColorPicker) {
                ColorTagPickerView { tag in
                    if let range = selectedRange {
                        store.applyFootnote(tag, to: range)
                    }
                }
            }
            .sheet(isPresented: $showPreview) {
                PreviewSheet(html: previewHTML)
            }
            .alert("Microphone access needed", isPresented: $showMicPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable microphone and speech recognition in Settings to dictate.")
            }
            .alert("Posted", isPresented: .constant(submittedURL != nil)) {
                Button("OK") { submittedURL = nil }
            } message: {
                Text(submittedURL ?? "")
            }
            .task {
                await store.loadChannels()
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 24) {
            Button {
                showColorPicker = true
            } label: {
                Label("Footnote", systemImage: "character.bubble")
            }
            .disabled(selectedRange == nil)

            MicButton(isRecording: stt.isRecording) {
                Task { await toggleDictation() }
            }

            Button {
                Task { await runPreview() }
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .disabled(store.draft.isEmpty)
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottomTrailing) {
            submitButton.padding(.trailing)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            if store.isSubmitting {
                ProgressView()
            } else {
                Text("Post").fontWeight(.semibold)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.draft.isEmpty || store.isSubmitting)
    }

    // MARK: - Actions

    private func toggleDictation() async {
        if stt.isRecording {
            stt.stop()
            return
        }
        let granted = await stt.requestAuthorization()
        guard granted else {
            showMicPermissionAlert = true
            return
        }
        stt.start { utterance in
            store.appendUtterance(utterance)
        }
    }

    private func runPreview() async {
        previewHTML = await store.preview()
        if previewHTML != nil { showPreview = true }
    }

    private func submit() async {
        if stt.isRecording { stt.stop() }
        if let created = await store.submit() {
            submittedURL = created.url
        }
    }
}

/// Shows the server-rendered HTML preview in a web view.
private struct PreviewSheet: View {
    let html: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let html {
                    HTMLView(html: html)
                } else {
                    ContentUnavailableView("No preview", systemImage: "eye.slash")
                }
            }
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
