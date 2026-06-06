//
//  CaptureView.swift
//  Atacama
//
//  The primary authoring screen: dictate a stream-of-consciousness draft, edit it,
//  add colortext footnotes to selected text, pick a channel, preview, and submit.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct CaptureView: View {
    @EnvironmentObject private var session: SessionManager
    @ObservedObject private var serverStore = ServerStore.shared
    @StateObject private var store = DraftStore.shared
    @StateObject private var stt = STTService()
    @StateObject private var tts = TTSService()

    @State private var selectedRange: Range<String.Index>?
    @State private var showColorPicker = false
    @State private var showPreview = false
    @State private var previewHTML: String?
    @State private var showMicPermissionAlert = false
    @State private var submittedURL: String?
    @State private var showServers = false
    @State private var showSubjectEditor = false

    /// Compact vertical space (landscape, or portrait with the keyboard up on small
    /// devices): hide the inline Subject field and channel picker, shrink the mic.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompact: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            VStack(spacing: isCompact ? 8 : 12) {
                if !isCompact {
                    TextField("Subject", text: $store.draft.subject)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }

                DraftEditorView(
                    text: $store.draft.body,
                    liveTranscript: stt.transcript,
                    selectedRange: $selectedRange,
                    isRecording: stt.isRecording,
                    onToggleDictation: { Task { await toggleDictation() } }
                )
                .padding(.horizontal)

                if !isCompact {
                    PostTargetPicker(
                        servers: serverStore.signedInServers,
                        channelsByServer: store.channelsByServer,
                        selection: $store.target
                    )
                    .padding(.horizontal)
                }

                controlBar
            }
            .navigationTitle("New post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(isCompact ? .inline : .automatic)
            #endif
            .toolbar {
                // In compact layouts the Subject field is hidden inline; expose it here.
                if isCompact {
                    ToolbarItem(placement: .principal) {
                        Button {
                            showSubjectEditor = true
                        } label: {
                            Label(
                                store.draft.subject.isEmpty ? "Subject" : store.draft.subject,
                                systemImage: "textformat"
                            )
                            .lineLimit(1)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Read draft aloud", systemImage: "speaker.wave.2") {
                            tts.speak(store.draft.body)
                        }
                        Button("Servers…", systemImage: "server.rack") {
                            showServers = true
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
                PreviewSheet(html: previewHTML, baseURL: store.targetServer?.apiBase)
            }
            .sheet(isPresented: $showServers) {
                ServerListView()
            }
            .sheet(isPresented: $showSubjectEditor) {
                SubjectEditorSheet(subject: $store.draft.subject)
                    .presentationDetents([.height(160)])
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
            // Reload channels when the set of signed-in servers changes (e.g. after
            // signing in/out from the Servers screen).
            .onChange(of: session.signedInServerIDs) {
                Task { await store.loadChannels() }
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            // Compact layouts hide the inline channel picker; surface it here as a
            // compact menu so the destination is still one tap away.
            if isCompact {
                PostTargetPicker(
                    servers: serverStore.signedInServers,
                    channelsByServer: store.channelsByServer,
                    selection: $store.target,
                    style: .compact
                )
                .buttonStyle(.bordered)
            }

            HStack(spacing: isCompact ? 16 : 24) {
                Button {
                    showColorPicker = true
                } label: {
                    Label("Footnote", systemImage: "character.bubble")
                        .labelStyle(.iconOnly)
                }
                .disabled(selectedRange == nil)

                Spacer()

                MicButton(isRecording: stt.isRecording, size: isCompact ? 56 : 80) {
                    Task { await toggleDictation() }
                }

                Spacer()

                Button {
                    Task { await runPreview() }
                } label: {
                    Label("Preview", systemImage: "eye")
                        .labelStyle(.iconOnly)
                }
                .disabled(store.draft.isEmpty)

                submitButton
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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
        // Switching from hand-editing to voice: drop the keyboard so the draft and
        // controls have the full screen while dictating.
        dismissKeyboard()
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

    private func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        #endif
    }
}

/// Small sheet for editing the post subject when the inline field is hidden in
/// compact (landscape) layouts.
private struct SubjectEditorSheet: View {
    @Binding var subject: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextField("Subject", text: $subject)
                .font(.headline)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .padding()
                .navigationTitle("Subject")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear { focused = true }
        }
    }
}

/// Shows the server-rendered HTML preview in a web view.
private struct PreviewSheet: View {
    let html: String?
    /// API base of the server the preview was rendered by, for asset resolution.
    var baseURL: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let html {
                    HTMLView(html: html, baseURL: baseURL)
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
