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
        if let selectedBlock {
            return selectedBlock.insights
        }
        return VineyardCanopyAnalytics.vineyardWideInsights(blocks: blocks)
    }

    private var useInlineEditor: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let wide = isWideLayout(geometry)

                    if wide {
                        wideLayout
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        phoneLayout(in: geometry)
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
                    .font(horizontalSizeClass == .compact ? .subheadline : .body)
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

    private func isWideLayout(_ geometry: GeometryProxy) -> Bool {
        geometry.size.width > geometry.size.height && geometry.size.width >= 700
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

    private var wideLayout: some View {
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
                wideRightPanel()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func wideRightPanel() -> some View {
        GeometryReader { geo in
            let topHeight = geo.size.height * PanelProportions.readings

            VStack(spacing: 0) {
                CanopySensorReadingsView(block: selectedBlock, allBlocks: blocks, layout: .regular)
                    .frame(height: topHeight)

                Divider()

                VineyardInsightsPanel(block: selectedBlock, insights: activeInsights)
                    .frame(height: geo.size.height - topHeight)
            }
        }
    }

    // MARK: - iPhone / portrait

    private func phoneLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            mapView()
                .frame(height: geometry.size.height * 0.34)

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
            } else {
                VStack(spacing: 0) {
                    CanopySensorReadingsView(
                        block: selectedBlock,
                        allBlocks: blocks,
                        layout: .compact
                    )
                    .frame(maxHeight: geometry.size.height * 0.36)

                    Divider()

                    VineyardInsightsPanel(block: selectedBlock, insights: activeInsights)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Golden ratio (φ ≈ 1.618): readings ≈ 38.2%, insights ≈ 61.8%
private enum PanelProportions {
    private static let phi: CGFloat = (1 + sqrt(5)) / 2
    static let readings: CGFloat = 1 / (1 + phi)
}
