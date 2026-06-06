//
//  PostTargetPicker.swift
//  Atacama
//
//  Picks where a post goes: a single flat list of `server / channel` rows across all
//  signed-in servers, sectioned by server. Replaces the single-server ChannelPicker
//  on the capture screen. See docs/backend-api.md.
//

import SwiftUI

struct PostTargetPicker: View {
    /// Signed-in servers offered as post destinations.
    let servers: [ServerConfig]
    /// Channels available per server id (from DraftStore.channelsByServer).
    let channelsByServer: [UUID: [Channel]]
    @Binding var selection: PostTarget?

    var body: some View {
        Picker("Post to", selection: $selection) {
            ForEach(servers) { server in
                let channels = sortedChannels(for: server.id)
                if !channels.isEmpty {
                    Section(server.name) {
                        ForEach(channels) { channel in
                            Text(channel.displayName)
                                .tag(Optional(PostTarget(serverID: server.id, channel: channel.name)))
                        }
                    }
                }
            }
        }
    }

    private func sortedChannels(for serverID: UUID) -> [Channel] {
        (channelsByServer[serverID] ?? []).sorted {
            if $0.group != $1.group { return $0.group < $1.group }
            return $0.displayName < $1.displayName
        }
    }
}
