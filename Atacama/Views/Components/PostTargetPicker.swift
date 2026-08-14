//
//  PostTargetPicker.swift
//  Atacama
//
//  Picks where a post appears. A single always-visible, tappable "Appears on"
//  button opens a menu of reader-site / channel choices across all signed-in
//  publisher servers. Crucially it stays visible and
//  tappable even before any channels have loaded — in that state it offers a route
//  to add or sign in to a server, so the destination control is never a
//  hidden/empty row. See docs/backend-api.md.
//

import SwiftUI

struct PostTargetPicker: View {
    /// Signed-in servers offered as post destinations.
    let servers: [ServerConfig]
    /// Channels available per server id (from DraftStore.channelsByServer).
    let channelsByServer: [UUID: [Channel]]
    @Binding var selection: PostTarget?
    /// Invoked from the menu to add or sign in to servers — the only path forward when
    /// no channels are available yet.
    var onManageServers: () -> Void = {}

    var body: some View {
        Menu {
            if hasAnyChannels {
                Picker("Appears on", selection: $selection) {
                    pickerOptions
                }
            } else {
                Text("No channels available yet")
            }
            Divider()
            Button("Add or sign in to a server…", systemImage: "server.rack", action: onManageServers)
        } label: {
            label
        }
        .buttonStyle(.plain)
    }

    /// The persistent, obviously-tappable button face.
    private var label: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperplane.fill")
                .font(.subheadline)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Appears on")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currentLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isChosen ? Color.primary : Color.accentColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var pickerOptions: some View {
        ForEach(servers) { server in
            let channels = sortedChannels(for: server.id)
            if !channels.isEmpty {
                ForEach(channelGroups(of: channels), id: \.header) { group in
                    Section(group.header.isEmpty ? server.name : "\(group.header) — via \(server.name)") {
                        ForEach(group.channels) { channel in
                            Text(channel.displayName)
                                .tag(Optional(PostTarget(serverID: server.id, channel: channel.name)))
                        }
                    }
                }
            }
        }
    }

    /// A run of channels sharing a `group`, rendered as one menu section.
    private struct ChannelGroup {
        let header: String
        let channels: [Channel]
    }

    /// Split a publisher's channels into menu sections by `Channel.group`, which
    /// the backend uses for the destination reader site. When an older backend
    /// omits the group this yields a single un-headered run. Channels with no
    /// group alongside grouped ones land in a trailing section under the server
    /// name rather than being dropped.
    private func channelGroups(of channels: [Channel]) -> [ChannelGroup] {
        guard channels.contains(where: { !$0.group.isEmpty }) else {
            return [ChannelGroup(header: "", channels: channels)]
        }
        // `channels` is already sorted by group, so equal groups are adjacent.
        var groups: [ChannelGroup] = []
        for channel in channels where !channel.group.isEmpty {
            if let last = groups.last, last.header == channel.group {
                groups[groups.count - 1] = ChannelGroup(
                    header: last.header,
                    channels: last.channels + [channel]
                )
            } else {
                groups.append(ChannelGroup(header: channel.group, channels: [channel]))
            }
        }
        let ungrouped = channels.filter { $0.group.isEmpty }
        if !ungrouped.isEmpty {
            groups.append(ChannelGroup(header: "", channels: ungrouped))
        }
        return groups
    }

    /// Whether the current selection points at a known signed-in server.
    private var isChosen: Bool {
        guard let selection else { return false }
        return servers.contains { $0.id == selection.serverID }
    }

    private var hasAnyChannels: Bool {
        channelsByServer.values.contains { !$0.isEmpty }
    }

    /// Short "reader site / channel" description of the current selection, or a
    /// publisher fallback for servers that predate destination-site metadata.
    private var currentLabel: String {
        guard isChosen, let selection,
              let server = servers.first(where: { $0.id == selection.serverID })
        else { return "Choose destination" }
        guard let channel = selection.channel else {
            return "\(server.name) / default"
        }
        let selectedChannel = (channelsByServer[server.id] ?? [])
            .first(where: { $0.name == channel })
        let channelName = selectedChannel?.displayName ?? channel
        let publicSite: String
        if let group = selectedChannel?.group, !group.isEmpty {
            publicSite = group
        } else {
            publicSite = server.name
        }
        return "\(publicSite) / \(channelName)"
    }

    private func sortedChannels(for serverID: UUID) -> [Channel] {
        (channelsByServer[serverID] ?? []).sorted {
            if $0.group != $1.group { return $0.group < $1.group }
            return $0.displayName < $1.displayName
        }
    }
}
