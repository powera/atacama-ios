//
//  CaptureView.swift
//  Atacama
//
//  The primary authoring screen: choose a destination, enter a title, dictate
//  sections, add colortext footnotes to selected text, preview, and submit.
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
    @State private var showTitleEditor = false
    @State private var showError = false

    /// Compact vertical space (landscape, or portrait with the keyboard up on small
    /// devices): hide the inline Title field and channel picker, shrink the mic.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompact: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            VStack(spacing: isCompact ? 8 : 12) {
                if !isCompact {
                    authoringHeader
                }

                DraftEditorView(
                    text: $store.draft.body,
                    liveTranscript: stt.transcript,
                    selectedRange: $selectedRange,
                    isRecording: stt.isRecording,
                    onToggleDictation: { Task { await toggleDictation() } }
                )
                .padding(.horizontal)

                controlBar
            }
            .navigationTitle("Write post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(isCompact ? .inline : .automatic)
            #endif
            .toolbar {
                // In compact layouts the Title field is hidden inline; expose it here.
                if isCompact {
                    ToolbarItem(placement: .principal) {
                        Button {
                            showTitleEditor = true
                        } label: {
                            Label(
                                store.draft.subject.isEmpty ? "Title" : store.draft.subject,
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
            .sheet(isPresented: $showTitleEditor) {
                TitleEditorSheet(title: $store.draft.subject)
                    .presentationDetents([.height(160)])
            }
            .alert("Microphone access needed", isPresented: $showMicPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable microphone and speech recognition in Settings to dictate.")
            }
            .alert("Post sent", isPresented: .constant(submittedURL != nil)) {
                Button("Write another") { submittedURL = nil }
            } message: {
                Text("Your draft was cleared. You’re back on this write-and-send screen for the next post.\n\n\(submittedURL ?? "")")
            }
            .alert("Couldn’t continue", isPresented: $showError) {
                Button("OK") { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
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

    private var authoringHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            PostTargetPicker(
                servers: serverStore.signedInServers,
                channelsByServer: store.channelsByServer,
                selection: $store.target
            )

            TextField("Title", text: $store.draft.subject)
                .font(.headline)
                .textFieldStyle(.roundedBorder)

            Text("Tap the mic to dictate. Tap New section between thoughts; sections are sent as four dashes (----). Select text to add a colortext footnote.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if serverStore.signedInServers.isEmpty {
                Button("Add or sign in to a server", systemImage: "server.rack") {
                    showServers = true
                }
                .font(.caption)
            } else if store.targetServer == nil {
                Text("Choose a server and channel before posting.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
    }

    private var controlBar: some View {
        VStack(spacing: isCompact ? 8 : 10) {
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

            HStack(spacing: 12) {
                Button {
                    showColorPicker = true
                } label: {
                    actionLabel("Footnote", systemImage: "character.bubble")
                }
                .disabled(selectedRange == nil)

                Button {
                    store.insertSectionBreak()
                } label: {
                    actionLabel("New section", systemImage: "text.badge.plus")
                }
                .disabled(store.draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task { await runPreview() }
                } label: {
                    actionLabel("Preview", systemImage: "eye")
                }
                .disabled(store.draft.isEmpty || store.targetServer == nil)
            }
            .buttonStyle(.bordered)

            HStack(spacing: isCompact ? 16 : 24) {
                Spacer()

                MicButton(isRecording: stt.isRecording, size: isCompact ? 56 : 80) {
                    Task { await toggleDictation() }
                }

                Spacer()

                submitButton
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        if isCompact {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
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
        .disabled(store.draft.isEmpty || store.targetServer == nil || store.isSubmitting)
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
        if previewHTML != nil {
            showPreview = true
        } else if store.lastError != nil {
            showError = true
        }
    }

    private func submit() async {
        if stt.isRecording { stt.stop() }
        if let created = await store.submit() {
            submittedURL = created.url
        } else if store.lastError != nil {
            showError = true
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

/// Small sheet for editing the post title when the inline field is hidden in
/// compact (landscape) layouts.
private struct TitleEditorSheet: View {
    @Binding var title: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextField("Title", text: $title)
                .font(.headline)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .padding()
                .navigationTitle("Title")
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
