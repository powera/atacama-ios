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
    /// Whether a channel refresh is currently in flight.
    var isLoading = false
    /// Channel load failures keyed by server id, surfaced directly in the menu.
    var errorsByServer: [UUID: String] = [:]
    @Binding var selection: PostTarget?
    /// Invoked from the menu to add or sign in to servers — the only path forward when
    /// no channels are available yet.
    var onManageServers: () -> Void = {}
    /// Invoked from the menu to retry GET /api/channels.
    var onRetry: () -> Void = {}

    var body: some View {
        Menu {
            if hasAnyChannels {
                Picker("Channel", selection: $selection) {
                    pickerOptions
                }
            } else if isLoading {
                Label("Loading channels…", systemImage: "arrow.triangle.2.circlepath")
            } else if !errorsByServer.isEmpty {
                errorOptions
            } else if servers.isEmpty {
                Text("No signed-in server")
            } else {
                Text("No channels returned")
            }

            Divider()
            Button("Reload channels", systemImage: "arrow.clockwise", action: onRetry)
                .disabled(servers.isEmpty || isLoading)
            Button("Servers…", systemImage: "server.rack", action: onManageServers)
        } label: {
            label
        }
        .buttonStyle(.plain)
    }

    /// The persistent, obviously-tappable button face.
    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.subheadline)
                .foregroundStyle(statusColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("Destination")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currentLabel)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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

    @ViewBuilder
    private var errorOptions: some View {
        ForEach(servers) { server in
            if let error = errorsByServer[server.id] {
                Section(server.name) {
                    Label(shortError(error), systemImage: "exclamationmark.triangle")
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

    private var statusIcon: String {
        if isLoading { return "arrow.triangle.2.circlepath" }
        if !errorsByServer.isEmpty { return "exclamationmark.triangle.fill" }
        return "paperplane.fill"
    }

    private var statusColor: Color {
        if !errorsByServer.isEmpty { return .orange }
        return isChosen ? .primary : .accentColor
    }

    /// Short "server / channel" description of the current selection, or a prompt.
    private var currentLabel: String {
        if isLoading && !hasAnyChannels { return "Loading channels…" }
        if !errorsByServer.isEmpty && !hasAnyChannels { return "Channels failed" }
        guard isChosen, let selection,
              let server = servers.first(where: { $0.id == selection.serverID })
        else { return "Choose server + channel" }
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

    private func shortError(_ error: String) -> String {
        error.count > 80 ? String(error.prefix(77)) + "…" : error
    }
}
