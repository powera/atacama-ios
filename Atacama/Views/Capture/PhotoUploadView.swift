//
//  PhotoUploadView.swift
//  Atacama
//
//  The photo-upload screen (the "Photo" tab): pick a photo from the library or
//  capture one, add a title/caption/location, choose a destination server+topic,
//  and upload it to newslettr (POST /api/images). Auth-gated like posting. The
//  destination reuses DraftStore's channel list and the shared PostTargetPicker.
//

import PhotosUI
import SwiftUI

struct PhotoUploadView: View {
    @EnvironmentObject private var session: SessionManager
    @ObservedObject private var serverStore = ServerStore.shared
    @ObservedObject private var draftStore = DraftStore.shared
    @StateObject private var store = PhotoUploadStore.shared

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showServers = false
    @State private var uploadedMessage: String?
    @State private var showError = false
    @State private var isDecoding = false

    /// Servers that advertise photo upload (older backends are excluded).
    /// `offersImageUpload` requires the authoring capability too: a reader-only
    /// content domain reports `images: true` for its photo *feed* while accepting
    /// no uploads at all.
    private var uploadServers: [ServerConfig] {
        serverStore.signedInServers.filter(\.offersImageUpload)
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                if store.imageData != nil {
                    detailsSection
                    destinationSection
                    uploadSection
                }
            }
            .navigationTitle("Add photo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Servers…", systemImage: "server.rack") { showServers = true }
                }
            }
            .sheet(isPresented: $showServers) { ServerListView() }
            #if os(iOS)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in handlePicked(data) }
                    .ignoresSafeArea()
            }
            #endif
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadPicked(item) }
            }
            .alert("Photo uploaded", isPresented: .constant(uploadedMessage != nil)) {
                Button("Add another") { uploadedMessage = nil }
            } message: {
                Text(uploadedMessage ?? "")
            }
            .alert("Couldn’t continue", isPresented: $showError) {
                Button("OK") { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
            .task { await draftStore.loadChannels() }
            .onChange(of: session.signedInServerIDs) {
                Task { await draftStore.loadChannels() }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var photoSection: some View {
        Section {
            if let data = store.imageData, let image = Self.previewImage(data) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(store.imageData == nil ? "Choose photo" : "Choose a different photo",
                      systemImage: "photo.on.rectangle")
            }
            #if os(iOS)
            Button {
                showCamera = true
            } label: {
                Label("Take photo", systemImage: "camera")
            }
            #endif
            if isDecoding {
                HStack { ProgressView(); Text("Preparing photo…").foregroundStyle(.secondary) }
            }
        } header: {
            Text("Photo")
        } footer: {
            if uploadServers.isEmpty {
                Text("Sign in to a newslettr server that supports photo uploads to add photos.")
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $store.title)
            TextField("Caption", text: $store.caption, axis: .vertical)
                .lineLimit(1 ... 4)
            TextField("Location", text: $store.location)
        }
    }

    private var destinationSection: some View {
        Section("Destination") {
            PostTargetPicker(
                servers: uploadServers,
                channelsByServer: draftStore.channelsByServer,
                selection: $store.target,
                onManageServers: { showServers = true }
            )
            Toggle("Publish now", isOn: $store.publishNow)
        }
    }

    private var uploadSection: some View {
        Section {
            Button {
                Task { await upload() }
            } label: {
                if store.isUploading {
                    HStack { ProgressView(); Text("Uploading…") }
                } else {
                    Text(store.publishNow ? "Upload & publish" : "Upload as draft")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!store.canUpload)
        } footer: {
            if !store.publishNow {
                Text("Draft photos are saved to caption or publish later in the publisher.")
            }
        }
    }

    // MARK: - Actions

    private func loadPicked(_ item: PhotosPickerItem) async {
        isDecoding = true
        defer { isDecoding = false }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                store.lastError = "Could not read that photo."
                showError = true
                return
            }
            handlePicked(raw)
        } catch {
            store.lastError = error.localizedDescription
            showError = true
        }
    }

    /// Normalize picked/captured bytes to JPEG and stage them for upload.
    private func handlePicked(_ raw: Data) {
        guard let jpeg = ImageEncoding.jpegData(from: raw) else {
            store.lastError = "That file is not a supported image."
            showError = true
            return
        }
        store.imageData = jpeg
    }

    private func upload() async {
        if let image = await store.upload() {
            uploadedMessage = image.isDraft
                ? "Saved as a draft on \(image.topic.name). Caption or publish it in the publisher."
                : "Published to \(image.topic.name)."
            pickerItem = nil
        } else if store.lastError != nil {
            showError = true
        }
    }

    // MARK: - Platform image preview

    #if canImport(UIKit)
    private static func previewImage(_ data: Data) -> Image? {
        UIImage(data: data).map(Image.init(uiImage:))
    }
    #elseif canImport(AppKit)
    private static func previewImage(_ data: Data) -> Image? {
        NSImage(data: data).map(Image.init(nsImage:))
    }
    #else
    private static func previewImage(_ data: Data) -> Image? { nil }
    #endif
}

#if os(iOS)
import UIKit

/// A minimal UIImagePickerController wrapper for capturing a photo with the
/// camera. Returns the captured image as JPEG data. iOS only — the macOS build
/// hides the "Take photo" button.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = ImageEncoding.jpegData(from: image) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
