//
//  ReadingView.swift
//  Atacama
//
//  The read-only feed: a list of published posts from the reading server,
//  filtered by topic and date range (mirroring the web reader). Reading is
//  public, so this works without sign-in. Tapping a post opens PostDetailView.
//

import SwiftUI

struct ReadingView: View {
    @EnvironmentObject private var reading: ReadingStore
    @EnvironmentObject private var serverStore: ServerStore
    @State private var showingFilters = false

    var body: some View {
        NavigationStack {
            Group {
                if reading.readingServer == nil {
                    ContentUnavailableView(
                        "No server",
                        systemImage: "tray",
                        description: Text("Add a newslettr server in Settings to start reading.")
                    )
                } else if reading.posts.isEmpty, !reading.isLoading {
                    ContentUnavailableView(
                        "No posts",
                        systemImage: "doc.text",
                        description: Text(reading.lastError ?? "Nothing matches the current filters.")
                    )
                } else {
                    feedList
                }
            }
            .navigationTitle("Read")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filters", systemImage: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                ReadingFiltersView()
                    .environmentObject(reading)
            }
            .overlay {
                if reading.isLoading, reading.posts.isEmpty {
                    ProgressView()
                }
            }
            .task { await reading.load() }
        }
    }

    private var filtersActive: Bool {
        reading.selectedTopic != nil || reading.since != nil || reading.until != nil
    }

    private var feedList: some View {
        List(reading.posts) { post in
            NavigationLink {
                PostDetailView(postID: post.id, fallbackTitle: post.title)
                    .environmentObject(reading)
            } label: {
                PostRowView(post: post)
            }
        }
        .listStyle(.plain)
        .refreshable { await reading.load() }
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
