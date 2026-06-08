//
//  ColorTagPickerView.swift
//  Atacama
//
//  Presents the AML colortext tags so the author can insert a new footnote at the
//  current caret location. Calls `onSelect` with the chosen tag.
//

import SwiftUI

struct ColorTagPickerView: View {
    @Binding var footnoteText: String
    let onSelect: (ColorTag) -> Void
    @Environment(\.dismiss) private var dismiss

    private var canInsert: Bool {
        !footnoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Footnote text")
                            .font(.headline)
                        TextEditor(text: $footnoteText)
                            .frame(minHeight: 110)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                if footnoteText.isEmpty {
                                    Text("Type the note to insert at the selected location…")
                                        .foregroundStyle(.secondary)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .allowsHitTesting(false)
                                }
                            }
                        Text("Choose a color below to insert the note.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)

                    ForEach(ColorTag.all) { tag in
                        Button {
                            guard canInsert else { return }
                            onSelect(tag)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Text(tag.sigil)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(.regularMaterial, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tag.name.capitalized)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(tag.meaning)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(canInsert ? .tint : .tertiary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(.quaternary)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canInsert)
                    }
                }
                .padding()
            }
            .navigationTitle("Insert footnote")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
