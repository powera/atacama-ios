//
//  ReadingView.swift
//  Atacama
//
//  The read-only feed: a list of published posts from the reading server,
//  filtered by topic and date range (mirroring the web reader). Reading is
//  public, so this works without sign-in. Tapping a post opens PostDetailView.
//
//  The toolbar menu also opens MutedChannelsView, which hides whole channels
//  from this tab for good — a standing preference, unlike the filters here.
//

import SwiftUI

struct ReadingView: View {
    @EnvironmentObject private var reading: ReadingStore
    @EnvironmentObject private var serverStore: ServerStore
    @State private var showingFilters = false
    @State private var showingMutedChannels = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                kindPicker
                Group {
                    if reading.readingServer == nil {
                        ContentUnavailableView(
                            "No server",
                            systemImage: "tray",
                            description: Text("Add a newslettr server in Settings to start reading.")
                        )
                    } else if reading.isEmpty, !reading.isLoading {
                        emptyState
                    } else {
                        feedContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Read")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // A menu rather than a bare Filters button: muting a channel
                    // is a standing preference and the date/topic filters are a
                    // transient slice, so they should not share one sheet — and
                    // muting has to stay reachable on Links and Quotes, where
                    // there is nothing to filter.
                    Menu {
                        if reading.kind.isFilterable {
                            Button("Filters…", systemImage: "line.3.horizontal.decrease.circle") {
                                showingFilters = true
                            }
                        }
                        Button("Muted channels…", systemImage: "eye.slash") {
                            showingMutedChannels = true
                        }
                    } label: {
                        Label("Options", systemImage: feedIsNarrowed ? "ellipsis.circle.fill" : "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                ReadingFiltersView()
                    .environmentObject(reading)
            }
            .sheet(isPresented: $showingMutedChannels) {
                MutedChannelsView()
                    .environmentObject(reading)
            }
            .overlay {
                if reading.isLoading, reading.isEmpty {
                    ProgressView()
                }
            }
            .task { await reading.load() }
            .onChange(of: reading.kind) { Task { await reading.load() } }
        }
    }

    /// Segmented control choosing which content type to read (Posts / Photos /
    /// Links / Quotes), limited to what the reading server advertises.
    private var kindPicker: some View {
        Picker("Content", selection: $reading.kind) {
            ForEach(reading.availableKinds) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Whether the feed is showing less than everything the server offers, from
    /// either a transient filter or a muted channel. Both fill the toolbar icon:
    /// what matters to the reader is that something is being held back.
    private var feedIsNarrowed: Bool {
        reading.selectedTopic != nil
            || reading.since != nil
            || reading.until != nil
            || (reading.kind.respectsMuting && reading.hasMutedChannels)
    }

    /// Empty feeds are not all the same: a feed emptied by muting looks identical
    /// to one with nothing published, so it says which it is and offers the way out.
    @ViewBuilder
    private var emptyState: some View {
        if reading.isEmptyOnlyBecauseOfMuting {
            ContentUnavailableView {
                Label("All muted", systemImage: "eye.slash")
            } description: {
                Text("Everything loaded here is in a muted channel.")
            } actions: {
                Button("Muted channels…") { showingMutedChannels = true }
            }
        } else {
            ContentUnavailableView(
                "Nothing here",
                systemImage: reading.kind.systemImage,
                description: Text(reading.lastError ?? "Nothing matches the current filters.")
            )
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        switch reading.kind {
        case .posts:
            List(reading.posts) { post in
                NavigationLink {
                    PostDetailView(postID: post.id, fallbackTitle: post.title, fallbackURL: post.url)
                        .environmentObject(reading)
                } label: {
                    PostRowView(post: post)
                }
                // The same web actions the detail view offers, without having to
                // open the post first.
                .contextMenu {
                    if !post.url.isEmpty, let url = URL(string: post.url) {
                        Link(destination: url) {
                            Label("View in Browser", systemImage: "safari")
                        }
                        ShareLink(item: url) {
                            Label("Share Link", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await reading.load() }
        case .photos:
            ImageGridView(images: reading.images)
                .refreshable { await reading.load() }
        case .links:
            List(reading.links) { link in
                if let url = URL(string: link.url) {
                    Link(destination: url) { LinkRowView(link: link) }
                } else {
                    LinkRowView(link: link)
                }
            }
            .listStyle(.plain)
            .refreshable { await reading.load() }
        case .quotes:
            List(reading.quotes) { quote in
                QuoteRowView(quote: quote)
            }
            .listStyle(.plain)
            .refreshable { await reading.load() }
        }
    }
}

/// Filter sheet: topic picker plus an optional date window. Applying reloads the
/// feed against the new filters.
private struct ReadingFiltersView: View {
    @EnvironmentObject private var reading: ReadingStore
    @Environment(\.dismiss) private var dismiss

    @State private var topicID: String = ""
    @State private var useSince = false
    @State private var sinceDate = Date()
    @State private var useUntil = false
    @State private var untilDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Topic") {
                    Picker("Topic", selection: $topicID) {
                        Text("All topics").tag("")
                        ForEach(reading.availableTopics, id: \.id) { topic in
                            Text(topic.name).tag(topic.id)
                        }
                    }
                }
                Section("Date range") {
                    Toggle("Since", isOn: $useSince)
                    if useSince {
                        DatePicker("From", selection: $sinceDate, displayedComponents: .date)
                    }
                    Toggle("Until", isOn: $useUntil)
                    if useUntil {
                        DatePicker("To", selection: $untilDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        topicID = ""
                        useSince = false
                        useUntil = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                }
            }
            .onAppear(perform: syncFromStore)
        }
    }

    private func syncFromStore() {
        topicID = reading.selectedTopic?.id ?? ""
        if let since = reading.since {
            useSince = true
            sinceDate = since
        }
        if let until = reading.until {
            useUntil = true
            untilDate = until
        }
    }

    private func apply() {
        reading.selectedTopic = reading.availableTopics.first { $0.id == topicID }
        reading.since = useSince ? sinceDate : nil
        reading.until = useUntil ? untilDate : nil
        dismiss()
        Task { await reading.load() }
    }
}
