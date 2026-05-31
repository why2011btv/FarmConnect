import SwiftUI

struct SensorDashboardView: View {
    @StateObject private var layoutStore = VineyardBlockLayoutStore()
    @State private var selectedBlockId: String?
    @State private var editingBlockId: String?
    @State private var isEditingLayout = false
    @State private var showLayoutEditor = false

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

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Vineyard Sensors")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditingLayout ? "Done editing" : "Edit blocks") {
                        if isEditingLayout {
                            isEditingLayout = false
                            showLayoutEditor = false
                        } else {
                            isEditingLayout = true
                            editingBlockId = editingBlockId ?? "b1"
                            showLayoutEditor = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showLayoutEditor, onDismiss: {
                isEditingLayout = false
                editingBlockId = nil
            }) {
                VineyardBlockLayoutEditor(
                    layoutStore: layoutStore,
                    editingBlockId: $editingBlockId
                )
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

            rightPanel(readingsFraction: 0.5, insightsFraction: 0.5)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - iPhone / portrait

    private func stackedLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            mapView()
                .frame(height: geometry.size.height * 0.42)

            Divider()

            rightPanel(
                readingsFraction: selectedBlock == nil ? 0.38 : 0.52,
                insightsFraction: selectedBlock == nil ? 0.62 : 0.48
            )
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
