import SwiftUI
import UIKit

struct VineyardBlockLayoutEditor: View {
    @ObservedObject var layoutStore: VineyardBlockLayoutStore
    @Binding var editingBlockId: String?
    @Environment(\.dismiss) private var dismiss

    @State private var importText = ""
    @State private var showImportSheet = false
    @State private var showCopiedAlert = false
    @State private var importFailed = false

    private let nudgeStep = 0.00005
    private let spanStep = 0.00003

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Adjust each rectangle to match the vineyard on the satellite map. Changes save automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Blocks") {
                    ForEach(layoutStore.rectangles) { rectangle in
                        Button {
                            editingBlockId = rectangle.id
                        } label: {
                            HStack {
                                Text(blockTitle(rectangle.id))
                                Spacer()
                                if editingBlockId == rectangle.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                    }
                }

                if let id = editingBlockId, layoutStore.rectangle(id: id) != nil {
                    Section("Position — \(blockTitle(id))") {
                        coordinateRow("Latitude", value: rect.centerLatitude) { delta in
                            layoutStore.updateRectangle(id: id) { $0.centerLatitude += delta }
                        }
                        coordinateRow("Longitude", value: rect.centerLongitude) { delta in
                            layoutStore.updateRectangle(id: id) { $0.centerLongitude += delta }
                        }
                        nudgePad(id: id)
                    }

                    Section("Size (half-span)") {
                        coordinateRow("N–S half span", value: rect.halfLatitudeSpan) { delta in
                            layoutStore.updateRectangle(id: id) { $0.growLatitude(by: delta) }
                        }
                        coordinateRow("E–W half span", value: rect.halfLongitudeSpan) { delta in
                            layoutStore.updateRectangle(id: id) { $0.growLongitude(by: delta) }
                        }
                    }

                    Section {
                        Button("Reset this block") {
                            layoutStore.resetBlock(id: id)
                        }
                    }
                }

                Section("All blocks") {
                    Button("Reset all to defaults", role: .destructive) {
                        layoutStore.resetToDefaults()
                        editingBlockId = "b1"
                    }
                    Button("Copy layout JSON") {
                        UIPasteboard.general.string = layoutStore.exportJSON()
                        showCopiedAlert = true
                    }
                    Button("Import layout JSON…") {
                        showImportSheet = true
                    }
                }
            }
            .navigationTitle("Edit block layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Copied", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Layout JSON copied to the clipboard. Paste into Notes or Messages to back up.")
            }
            .alert("Import failed", isPresented: $importFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("JSON must contain exactly 8 blocks with ids b1–b8.")
            }
            .sheet(isPresented: $showImportSheet) {
                importSheet
            }
        }
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste layout JSON")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $importText)
                    .font(.system(.caption, design: .monospaced))
                    .border(Color.secondary.opacity(0.3))
            }
            .padding()
            .navigationTitle("Import layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImportSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if layoutStore.importJSON(importText) {
                            showImportSheet = false
                        } else {
                            importFailed = true
                        }
                    }
                }
            }
        }
    }

    private func blockTitle(_ id: String) -> String {
        layoutStore.blocks.first { $0.id == id }?.name ?? id
    }

    private func coordinateRow(
        _ label: String,
        value: Double,
        apply: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.5f", value))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Stepper("", onIncrement: { apply(spanStep) }, onDecrement: { apply(-spanStep) })
                .labelsHidden()
        }
    }

    private func nudgePad(id: String) -> some View {
        VStack(spacing: 8) {
            Button("North") {
                layoutStore.updateRectangle(id: id) { $0.nudge(latitude: nudgeStep, longitude: 0) }
            }
            HStack {
                Button("West") {
                    layoutStore.updateRectangle(id: id) { $0.nudge(latitude: 0, longitude: -nudgeStep) }
                }
                Spacer()
                Button("East") {
                    layoutStore.updateRectangle(id: id) { $0.nudge(latitude: 0, longitude: nudgeStep) }
                }
            }
            Button("South") {
                layoutStore.updateRectangle(id: id) { $0.nudge(latitude: -nudgeStep, longitude: 0) }
            }
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }
}
