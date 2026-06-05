//
//  ChannelPicker.swift
//  Atacama
//
//  Picker for the post's channel, grouped by channel group.
//

import SwiftUI

struct ChannelPicker: View {
    let channels: [Channel]
    @Binding var selection: String?

    private var grouped: [(group: String, channels: [Channel])] {
        let groups = Dictionary(grouping: channels, by: { $0.group })
        return groups
            .map { (group: $0.key, channels: $0.value.sorted { $0.displayName < $1.displayName }) }
            .sorted { $0.group < $1.group }
    }

    var body: some View {
        Picker("Channel", selection: $selection) {
            ForEach(grouped, id: \.group) { section in
                Section(section.group) {
                    ForEach(section.channels) { channel in
                        Text(channel.displayName).tag(Optional(channel.name))
                    }
                }
            }
        }
    }
}
