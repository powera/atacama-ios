//
//  MutedChannelsView.swift
//  Atacama
//
//  Sheet for hiding channels from the Read tab. Unlike ReadingView's filter
//  sheet — a transient "show me this slice" — muting is a standing preference,
//  which is why it gets its own screen rather than a section next to a Clear
//  button that would look like it un-mutes.
//
//  The preference is stored on the device (see ReadingStore.mutedChannels): the
//  read feeds are public and carry no token, so there is no user identity on the
//  request for the server to key a per-reader preference to.
//

import SwiftUI

struct MutedChannelsView: View {
    @EnvironmentObject private var reading: ReadingStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if reading.readingServer == nil {
                    ContentUnavailableView(
                        "No server",
                        systemImage: "tray",
                        description: Text("Add a newslettr server to choose what to read.")
                    )
                } else if channels.isEmpty {
                    // The channel list is built from what the feeds have
                    // returned so far — GET /api/channels needs a token, and a
                    // read-only content domain does not serve it at all — so a
                    // reader who has not loaded anything yet has nothing to mute.
                    ContentUnavailableView(
                        "No channels yet",
                        systemImage: "eye.slash",
                        description: Text("Channels appear here once the feed has loaded something to read.")
                    )
                } else {
                    channelList
                }
            }
            .navigationTitle("Muted channels")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if reading.hasMutedChannels {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Unmute all") { reading.unmuteAll() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var channelList: some View {
        Form {
            Section {
                ForEach(channels, id: \.id) { channel in
                    Toggle(displayName(of: channel), isOn: binding(for: channel))
                }
            } header: {
                Text("Hide from Read")
            } footer: {
                // Says both what muting covers and where it lives, because
                // neither is obvious: quotes carry no channel in the API, and
                // nothing here syncs to the server or to another device.
                Text(
                    "Muted channels are hidden from posts, photos and links on this device. "
                        + "Quotes have no channel, so they are always shown."
                )
            }
        }
    }

    private var channels: [TopicRef] { reading.manageableChannels }

    /// A channel muted before its name was ever cached is listed by its slug, so
    /// fall back to the id rather than rendering a blank, untappable row.
    private func displayName(of channel: TopicRef) -> String {
        channel.name.isEmpty ? channel.id : channel.name
    }

    /// Toggling writes straight through to the store, which re-filters content it
    /// already holds — so hiding a channel is immediate and costs no request.
    private func binding(for channel: TopicRef) -> Binding<Bool> {
        Binding(
            get: { reading.isMuted(channel.id) },
            set: { reading.setMuted($0, channel: channel.id) }
        )
    }
}
