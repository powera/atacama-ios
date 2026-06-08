//
//  CaptureView.swift
//  Atacama
//
//  The primary authoring screen: choose a destination, enter a title, dictate
//  sections, add colortext footnotes to selected text, preview, and submit.
//
//  Layout is intentionally iPhone-first: title + destination are compact setup
//  fields, the draft editor gets the flexible space, and secondary actions live in a
//  Tools menu so they cannot truncate into unusable one-letter buttons.
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
    @State private var keyboardVisible = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Compact vertical space (landscape, or the keyboard up on small devices): shrink
    /// chrome so the editor keeps the most room.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompact: Bool { verticalSizeClass == .compact || keyboardVisible }
    private var micSize: CGFloat { dynamicTypeSize.isAccessibilitySize || isCompact ? 56 : 68 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                authoringHeader

                DraftEditorView(
                    text: $store.draft.body,
                    liveTranscript: stt.transcript,
                    selectedRange: $selectedRange,
                    isRecording: stt.isRecording,
                    onToggleDictation: { Task { await toggleDictation() } }
                )
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
                .layoutPriority(1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            // When a hardware/software keyboard is active, give the visible area to the
            // focused field/editor. The editor itself supplies a tiny keyboard accessory
            // with mic + Done, so the full bottom bar is not needed above the keyboard.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !keyboardVisible {
                    controlBar
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
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
            #endif
        }
    }

    private var authoringHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Write post")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                headerMenu
            }

            TextField("Title", text: $store.draft.subject)
                .font(.headline)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.next)

            PostTargetPicker(
                servers: serverStore.signedInServers,
                channelsByServer: store.channelsByServer,
                isLoading: store.isLoadingChannels,
                errorsByServer: store.channelErrorsByServer,
                selection: $store.target,
                onManageServers: { showServers = true },
                onRetry: { Task { await store.loadChannels() } }
            )
        }
    }

    private var headerMenu: some View {
        Menu {
            Button("Read draft aloud", systemImage: "speaker.wave.2") {
                tts.speak(store.draft.body)
            }
            Button("Servers…", systemImage: "server.rack") {
                showServers = true
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .font(.title3)
        }
        .accessibilityLabel("More options")
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            toolsMenu
                .frame(minWidth: 70, alignment: .leading)

            Spacer(minLength: 0)

            MicButton(isRecording: stt.isRecording, size: micSize) {
                Task { await toggleDictation() }
            }

            Spacer(minLength: 0)

            submitButton
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var toolsMenu: some View {
        Menu {
            Button("Hide selected text", systemImage: "character.bubble") {
                showColorPicker = true
            }
            .disabled(selectedRange == nil)

            Button("New section", systemImage: "text.badge.plus") {
                store.insertSectionBreak()
            }
            .disabled(store.draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Preview", systemImage: "eye") {
                Task { await runPreview() }
            }
            .disabled(store.draft.isEmpty || store.targetServer == nil)
        } label: {
            Label("Tools", systemImage: "slider.horizontal.3")
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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
