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
    enum Style {
        /// Full inline picker row (portrait / roomy layouts).
        case inline
        /// Compact menu button showing the current target, for space-constrained layouts.
        case compact
    }

    /// Signed-in servers offered as post destinations.
    let servers: [ServerConfig]
    /// Channels available per server id (from DraftStore.channelsByServer).
    let channelsByServer: [UUID: [Channel]]
    @Binding var selection: PostTarget?
    var style: Style = .inline

    var body: some View {
        switch style {
        case .inline:
            inlinePicker
        case .compact:
            compactMenu
        }
    }

    private var inlinePicker: some View {
        Picker("Post to", selection: $selection) {
            pickerOptions
        }
    }

    private var compactMenu: some View {
        Menu {
            Picker("Post to", selection: $selection) {
                pickerOptions
            }
        } label: {
            Label(currentLabel, systemImage: "paperplane")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var pickerOptions: some View {
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

    /// Short "server / channel" description of the current selection for the compact label.
    private var currentLabel: String {
        guard let selection,
              let server = servers.first(where: { $0.id == selection.serverID })
        else { return "Choose channel" }
        guard let channel = selection.channel else {
            return "\(server.name) / default"
        }
        let channelName = (channelsByServer[server.id] ?? [])
            .first(where: { $0.name == channel })?
            .displayName ?? channel
        return "\(server.name) / \(channelName)"
    }

    private func sortedChannels(for serverID: UUID) -> [Channel] {
        (channelsByServer[serverID] ?? []).sorted {
            if $0.group != $1.group { return $0.group < $1.group }
            return $0.displayName < $1.displayName
        }
    }
}
