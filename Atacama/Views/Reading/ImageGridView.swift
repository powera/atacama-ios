//
//  ImageGridView.swift
//  Atacama
//
//  The photo feed: a grid of thumbnails loaded from a newslettr site's public
//  image feed (GET /api/images). Tapping a photo opens ImageDetailView with the
//  full image and its metadata. Images load by URL via AsyncImage.
//

import SwiftUI

struct ImageGridView: View {
    let images: [AtacamaImage]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(images) { image in
                    NavigationLink {
                        ImageDetailView(image: image)
                    } label: {
                        thumbnail(for: image)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
    }

    private func thumbnail(for image: AtacamaImage) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                AsyncImage(url: URL(string: image.url)) { phase in
                    switch phase {
                    case let .success(img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Color.clear
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

/// A single photo with its metadata, shown when a grid thumbnail is tapped.
struct ImageDetailView: View {
    let image: AtacamaImage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AsyncImage(url: URL(string: image.url)) { phase in
                    switch phase {
                    case let .success(img):
                        img.resizable().scaledToFit()
                    case .failure:
                        ContentUnavailableView("Couldn’t load photo", systemImage: "photo")
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    if !image.title.isEmpty {
                        Text(image.title).font(.title3.weight(.semibold))
                    }
                    if !image.caption.isEmpty {
                        Text(image.caption).font(.body)
                    }
                    metadata
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical)
        }
        .navigationTitle(image.title.isEmpty ? "Photo" : image.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(image.topic.name, systemImage: "tag")
            if !image.location.isEmpty {
                Label(image.location, systemImage: "mappin.and.ellipse")
            }
            if let captured = image.capturedAt {
                Label(captured.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            }
            let camera = "\(image.cameraMake) \(image.cameraModel)".trimmingCharacters(in: .whitespaces)
            if !camera.isEmpty {
                Label(camera, systemImage: "camera")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}
