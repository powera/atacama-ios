//
//  PostTargetPicker.swift
//  Atacama
//
//  Picks where a post goes. A single always-visible, tappable "Post to" button that
//  opens a menu of `server / channel` choices across all signed-in servers, sectioned
//  by server. Crucially it stays visible and tappable even before any channels have
//  loaded — in that state it offers a route to add or sign in to a server, so the
//  destination control is never a hidden/empty row. See docs/backend-api.md.
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
                Picker("Post to", selection: $selection) {
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
                Text("Post to")
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
                Section(server.name) {
                    ForEach(channels) { channel in
                        Text(channel.displayName)
                            .tag(Optional(PostTarget(serverID: server.id, channel: channel.name)))
                    }
                }
            }
        }
    }

    /// Whether the current selection points at a known signed-in server.
    private var isChosen: Bool {
        guard let selection else { return false }
        return servers.contains { $0.id == selection.serverID }
    }

    private var hasAnyChannels: Bool {
        channelsByServer.values.contains { !$0.isEmpty }
    }

    /// Short "server / channel" description of the current selection, or a prompt.
    private var currentLabel: String {
        guard isChosen, let selection,
              let server = servers.first(where: { $0.id == selection.serverID })
        else { return "Choose destination" }
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
