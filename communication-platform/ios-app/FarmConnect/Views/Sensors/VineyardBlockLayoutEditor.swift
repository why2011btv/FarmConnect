import SwiftUI
import UIKit

enum VineyardBlockLayoutEditorStyle {
    case sidebar
    case sheet
}

struct VineyardBlockLayoutEditor: View {
    @ObservedObject var layoutStore: VineyardBlockLayoutStore
    @Binding var editingBlockId: String?
    var style: VineyardBlockLayoutEditorStyle = .sheet
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var importText = ""
    @State private var showImportSheet = false
    @State private var showCopiedAlert = false
    @State private var importFailed = false
    @State private var useFineNudge = false

    private var nudgeStep: Double { useFineNudge ? 0.00002 : 0.00008 }
    private var spanStep: Double { useFineNudge ? 0.000015 : 0.00005 }
    private var rotationStep: Double { useFineNudge ? 0.5 : 2 }

    var body: some View {
        Group {
            switch style {
            case .sidebar:
                sidebarBody
            case .sheet:
                NavigationStack { editorList }
                    .navigationTitle("Edit block layout")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { sheetToolbar }
            }
        }
        .alert("Copied", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Layout JSON copied to the clipboard.")
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

    private var sidebarBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Block layout")
                    .font(.headline)
                Spacer()
                Button("Done") { finishEditing() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            editorList
        }
        .background(Color(.systemGroupedBackground))
    }

    private var editorList: some View {
        List {
            helpSection
            blockPickerSection
            if let id = editingBlockId {
                selectedBlockSection(id: id)
            }
            utilitiesSection
        }
        .listStyle(.insetGrouped)
    }

    private var helpSection: some View {
        Section {
            Text("Drag the numbered marker on the map, or use the controls below. Changes save automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Toggle("Fine adjustments", isOn: $useFineNudge)
        }
    }

    private var blockPickerSection: some View {
        Section("Select block") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(layoutStore.rectangles) { rectangle in
                        blockChip(rectangle.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private func blockChip(_ id: String) -> some View {
        let selected = editingBlockId == id
        return Button {
            editingBlockId = id
        } label: {
            Text(blockTitle(id))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func selectedBlockSection(id: String) -> some View {
        Group {
            Section("Move — \(blockTitle(id))") {
                nudgePad(id: id)
            }

            Section("Rotate") {
                if let rect = layoutStore.rectangle(id: id) {
                    HStack {
                        Text("\(Int(rect.rotationDegrees))°")
                            .font(.title2.bold().monospacedDigit())
                            .frame(width: 56, alignment: .leading)
                        Slider(
                            value: rotationBinding(id: id),
                            in: -45...45,
                            step: rotationStep
                        )
                    }
                    HStack {
                        adjustButton("−2°") {
                            layoutStore.updateRectangle(id: id) { $0.rotate(by: -rotationStep) }
                        }
                        adjustButton("+2°") {
                            layoutStore.updateRectangle(id: id) { $0.rotate(by: rotationStep) }
                        }
                        adjustButton("0°") {
                            layoutStore.updateRectangle(id: id) { $0.rotationDegrees = 0 }
                        }
                    }
                }
            }

            Section("Size") {
                if let rect = layoutStore.rectangle(id: id) {
                    sizeRow("Length (N–S)", value: rect.halfLatitudeSpan * 2) { delta in
                        layoutStore.updateRectangle(id: id) { $0.growLatitude(by: delta) }
                    }
                    sizeRow("Width (E–W)", value: rect.halfLongitudeSpan * 2) { delta in
                        layoutStore.updateRectangle(id: id) { $0.growLongitude(by: delta) }
                    }
                }
            }

            Section {
                Button("Reset this block") {
                    layoutStore.resetBlock(id: id)
                }
            }
        }
    }

    private var utilitiesSection: some View {
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

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { finishEditing() }
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

    private func finishEditing() {
        if style == .sheet {
            dismiss()
        }
        onDone?()
    }

    private func blockTitle(_ id: String) -> String {
        layoutStore.blocks.first { $0.id == id }?.name ?? id
    }

    private func rotationBinding(id: String) -> Binding<Double> {
        Binding(
            get: { layoutStore.rectangle(id: id)?.rotationDegrees ?? 0 },
            set: { newValue in
                layoutStore.updateRectangle(id: id) { $0.rotationDegrees = newValue }
            }
        )
    }

    private func nudgePad(id: String) -> some View {
        VStack(spacing: 10) {
            adjustButton("↑ North", large: true) {
                layoutStore.updateRectangle(id: id) { $0.nudge(latitude: nudgeStep, longitude: 0) }
            }
            HStack(spacing: 10) {
                adjustButton("← West", large: true) {
                    layoutStore.updateRectangle(id: id) { $0.nudge(latitude: 0, longitude: -nudgeStep) }
                }
                adjustButton("East →", large: true) {
                    layoutStore.updateRectangle(id: id) { $0.nudge(latitude: 0, longitude: nudgeStep) }
                }
            }
            adjustButton("↓ South", large: true) {
                layoutStore.updateRectangle(id: id) { $0.nudge(latitude: -nudgeStep, longitude: 0) }
            }
        }
        .listRowBackground(Color.clear)
    }

    private func sizeRow(
        _ label: String,
        value: Double,
        apply: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.4f°", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                adjustButton("Smaller") { apply(-spanStep) }
                adjustButton("Larger") { apply(spanStep) }
            }
        }
        .padding(.vertical, 4)
    }

    private func adjustButton(_ title: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(large ? .body.weight(.semibold) : .subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, large ? 14 : 10)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .buttonStyle(.plain)
    }
}
