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
            pickerContent
            .navigationTitle("Insert footnote")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var pickerContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                footnoteEditor
                colorTagButtons
            }
            .padding()
        }
    }

    private var footnoteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Footnote text")
                .font(.headline)

            TextEditor(text: $footnoteText)
                .frame(minHeight: 110)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    footnotePlaceholder
                }

            Text("Choose a color below to insert the note.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var footnotePlaceholder: some View {
        if footnoteText.isEmpty {
            Text("Type the note to insert at the selected location…")
                .foregroundStyle(.secondary)
                .padding(16)
                .allowsHitTesting(false)
        }
    }

    private var colorTagButtons: some View {
        ForEach(ColorTag.all) { tag in
            colorTagButton(for: tag)
        }
    }

    private func colorTagButton(for tag: ColorTag) -> some View {
        Button {
            insert(tag)
        } label: {
            ColorTagRow(tag: tag, canInsert: canInsert)
        }
        .buttonStyle(.plain)
        .disabled(!canInsert)
    }

    private func insert(_ tag: ColorTag) {
        guard canInsert else { return }
        onSelect(tag)
        dismiss()
    }
}

private struct ColorTagRow: View {
    let tag: ColorTag
    let canInsert: Bool

    var body: some View {
        HStack(spacing: 14) {
            sigil
            titleAndMeaning
            Spacer()
            addIcon
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

    private var sigil: some View {
        Text(tag.sigil)
            .font(.title2)
            .frame(width: 40, height: 40)
            .background(.regularMaterial, in: Circle())
    }

    private var titleAndMeaning: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tag.name.capitalized)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Text(tag.meaning)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var addIcon: some View {
        if canInsert {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
        } else {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tertiary)
        }
    }
}
