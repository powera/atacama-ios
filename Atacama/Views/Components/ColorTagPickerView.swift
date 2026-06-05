//
//  ColorTagPickerView.swift
//  Atacama
//
//  Presents the AML colortext tags so the author can wrap selected text in a
//  footnote. Calls `onSelect` with the chosen tag.
//

import SwiftUI

struct ColorTagPickerView: View {
    let onSelect: (ColorTag) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ColorTag.all) { tag in
                Button {
                    onSelect(tag)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(tag.sigil)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(tag.name.capitalized)
                                .font(.body)
                            Text(tag.meaning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Add footnote")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
