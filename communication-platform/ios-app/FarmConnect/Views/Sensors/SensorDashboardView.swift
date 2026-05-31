import SwiftUI

struct SensorDashboardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var layoutStore = VineyardBlockLayoutStore()
    @State private var selectedBlockId: String?
    @State private var editingBlockId: String?
    @State private var isEditingLayout = false
    @State private var showLayoutEditorSheet = false

    private var blocks: [VineyardDemoBlock] {
        layoutStore.blocks
    }

    private var selectedBlock: VineyardDemoBlock? {
        guard let selectedBlockId else { return nil }
        return blocks.first { $0.id == selectedBlockId }
    }

    private var activeInsights: [VineyardBlockInsight] {
        selectedBlock?.insights ?? VineyardDemoData.generalInsights
    }

    private var useInlineEditor: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let sideBySide = geometry.size.width > geometry.size.height
                        && geometry.size.width >= 700

                    if sideBySide {
                        sideBySideLayout
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        stackedLayout(in: geometry)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Vineyard Sensors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditingLayout ? "Done editing" : "Edit blocks") {
                        toggleLayoutEditing()
                    }
                }
            }
            .sheet(isPresented: $showLayoutEditorSheet, onDismiss: {
                isEditingLayout = false
                editingBlockId = nil
            }) {
                VineyardBlockLayoutEditor(
                    layoutStore: layoutStore,
                    editingBlockId: $editingBlockId,
                    style: .sheet,
                    onDone: {
                        isEditingLayout = false
                        editingBlockId = nil
                    }
                )
            }
        }
    }

    private func toggleLayoutEditing() {
        if isEditingLayout {
            isEditingLayout = false
            showLayoutEditorSheet = false
            editingBlockId = nil
        } else {
            isEditingLayout = true
            editingBlockId = editingBlockId ?? "b1"
            if !useInlineEditor {
                showLayoutEditorSheet = true
            }
        }
    }

    private func mapView() -> some View {
        VineyardHealthMapView(
            blocks: blocks,
            selectedBlockId: $selectedBlockId,
            isEditingLayout: isEditingLayout,
            editingBlockId: $editingBlockId,
            onMoveBlock: { id, lat, lng in
                layoutStore.updateRectangle(id: id) {
                    $0.centerLatitude = lat
                    $0.centerLongitude = lng
                }
            }
        )
    }

    // MARK: - iPad landscape / wide

    private var sideBySideLayout: some View {
        HStack(spacing: 0) {
            mapView()
                .frame(maxWidth: .infinity)

            Divider()

            if isEditingLayout, useInlineEditor {
                VineyardBlockLayoutEditor(
                    layoutStore: layoutStore,
                    editingBlockId: $editingBlockId,
                    style: .sidebar,
                    onDone: {
                        isEditingLayout = false
                        editingBlockId = nil
                    }
                )
                .frame(width: 360)
            } else {
                rightPanel(readingsFraction: 0.5, insightsFraction: 0.5)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - iPhone / portrait

    private func stackedLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            mapView()
                .frame(height: geometry.size.height * (isEditingLayout ? 0.55 : 0.42))

            if isEditingLayout, useInlineEditor {
                VineyardBlockLayoutEditor(
                    layoutStore: layoutStore,
                    editingBlockId: $editingBlockId,
                    style: .sidebar,
                    onDone: {
                        isEditingLayout = false
                        editingBlockId = nil
                    }
                )
                .frame(height: geometry.size.height * 0.45)
            } else {
                Divider()
                rightPanel(
                    readingsFraction: selectedBlock == nil ? 0.38 : 0.52,
                    insightsFraction: selectedBlock == nil ? 0.62 : 0.48
                )
            }
        }
    }

    private func rightPanel(readingsFraction: CGFloat, insightsFraction: CGFloat) -> some View {
        GeometryReader { geo in
            let readingsHeight = geo.size.height * readingsFraction
            let insightsHeight = geo.size.height * insightsFraction

            VStack(spacing: 0) {
                CanopySensorReadingsView(block: selectedBlock, allBlocks: blocks)
                    .frame(height: readingsHeight)

                Divider()

                VineyardInsightsPanel(
                    block: selectedBlock,
                    insights: activeInsights
                )
                .frame(height: insightsHeight)
            }
        }
    }
}
