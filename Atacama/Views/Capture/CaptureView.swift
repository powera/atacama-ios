//
//  CaptureView.swift
//  Atacama
//
//  The primary authoring screen: choose a destination, enter a title, dictate
//  sections, add colortext footnotes to selected text, preview, and submit.
//
//  Layout: an inline navigation title keeps the chrome small, a compact header
//  (destination + title) sits up top, the draft editor fills all remaining space,
//  and the mic/post controls live in a bottom bar pinned via `safeAreaInset` so they
//  stay above the keyboard and reachable on any screen size.
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
    @State private var showError = false

    /// Compact vertical space (landscape, or the keyboard up on small devices): drop the
    /// instructional hint and shrink the mic so the editor keeps the most room.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompact: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            VStack(spacing: isCompact ? 8 : 12) {
                authoringHeader

                DraftEditorView(
                    text: $store.draft.body,
                    liveTranscript: stt.transcript,
                    selectedRange: $selectedRange,
                    isRecording: stt.isRecording,
                    onToggleDictation: { Task { await toggleDictation() } }
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Write post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
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
            // Pin the mic/post controls to the bottom. As a safe-area inset they ride
            // above the keyboard, so they stay reachable while hand-editing.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controlBar
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
                selection: $store.target,
                onManageServers: { showServers = true }
            )

            TextField("Title", text: $store.draft.subject)
                .font(.headline)
                .textFieldStyle(.roundedBorder)

            if !isCompact {
                Text("Tap the mic to dictate. Tap New section between thoughts (sent as ----). Select text to add a colortext footnote.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: isCompact ? 8 : 12) {
            HStack(spacing: 10) {
                actionButton(
                    "Footnote",
                    systemImage: "character.bubble",
                    disabled: selectedRange == nil
                ) { showColorPicker = true }

                actionButton(
                    "New section",
                    systemImage: "text.badge.plus",
                    disabled: store.draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) { store.insertSectionBreak() }

                actionButton(
                    "Preview",
                    systemImage: "eye",
                    disabled: store.draft.isEmpty || store.targetServer == nil
                ) { Task { await runPreview() } }
            }

            // Mic centered, Post trailing — Post stays put regardless of mic size.
            ZStack {
                MicButton(isRecording: stt.isRecording, size: isCompact ? 52 : 72) {
                    Task { await toggleDictation() }
                }
                HStack {
                    Spacer()
                    submitButton
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, isCompact ? 8 : 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// One of the bordered editing actions. Equal-width and scaling so the labels show
    /// fully on roomy screens and degrade gracefully instead of clipping to one letter.
    private func actionButton(
        _ title: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                // A ternary can't unify the two concrete LabelStyle types, so branch.
                if isCompact {
                    Label(title, systemImage: systemImage).labelStyle(.iconOnly)
                } else {
                    Label(title, systemImage: systemImage).labelStyle(.titleAndIcon)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
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
