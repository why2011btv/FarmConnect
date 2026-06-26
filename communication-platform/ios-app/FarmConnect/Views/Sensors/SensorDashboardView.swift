import MapKit
import SwiftUI

struct SensorDashboardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var layoutStore = VineyardBlockLayoutStore()
    @State private var selectedBlockId: String?
    @State private var editingBlockId: String?
    @State private var isEditingLayout = false
    @State private var showLayoutEditorSheet = false
    @State private var showGeneratorSheet = false

    private var mode: LayoutMode { layoutStore.mode }

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

    // MARK: - Camera region per mode

    private var activeRegion: MKCoordinateRegion {
        switch mode {
        case .demo:
            return VineyardDemoData.mapRegion
        case .planning:
            if let profile = layoutStore.activeProfile {
                return profile.region
            }
            return VineyardLayoutGenerator.region(forRectangles: layoutStore.rectangles)
                ?? VineyardDemoData.mapRegion
        }
    }

    /// Changing this string retargets the map camera (mode switch or new vineyard) without
    /// tearing the map down.
    private var cameraKey: String {
        "\(mode.rawValue)|\(layoutStore.activeProfile?.name ?? "default")|\(layoutStore.rectangles.count)"
    }

    private var planningParcels: [[CLLocationCoordinate2D]] {
        guard mode == .planning else { return [] }
        return layoutStore.activeProfile?.parcelCoordinates ?? []
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
            .toolbar { dashboardToolbar }
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
            .sheet(isPresented: $showGeneratorSheet) {
                VineyardGeneratorView(
                    layoutStore: layoutStore,
                    onDone: {
                        selectedBlockId = nil
                        editingBlockId = nil
                        isEditingLayout = false
                    }
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            AccountMenuButton()
        }
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: modeBinding) {
                ForEach(LayoutMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
        }
        ToolbarItem(placement: .topBarTrailing) {
            trailingMenu
        }
    }

    @ViewBuilder
    private var trailingMenu: some View {
        switch mode {
        case .planning:
            Menu {
                Button {
                    showGeneratorSheet = true
                } label: {
                    Label("New vineyard…", systemImage: "plus.viewfinder")
                }
                Button {
                    toggleLayoutEditing()
                } label: {
                    Label(isEditingLayout ? "Done editing" : "Edit blocks", systemImage: "slider.horizontal.3")
                }
                .disabled(layoutStore.rectangles.isEmpty)
                if !layoutStore.rectangles.isEmpty {
                    Button {
                        layoutStore.promoteActiveLayoutToDemo()
                        layoutStore.setMode(.demo)
                    } label: {
                        Label("Use as demo layout", systemImage: "square.and.arrow.down.on.square")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        case .demo:
            // Presentation-locked: editing is a de-emphasized, office-prep opt-in.
            Menu {
                Button {
                    toggleLayoutEditing()
                } label: {
                    Label(isEditingLayout ? "Done editing" : "Edit blocks (prep)", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var modeBinding: Binding<LayoutMode> {
        Binding(
            get: { layoutStore.mode },
            set: { switchMode(to: $0) }
        )
    }

    private func switchMode(to next: LayoutMode) {
        guard next != layoutStore.mode else { return }
        // Clear all edit state so a mid-edit gesture can't land on the newly active slot.
        isEditingLayout = false
        showLayoutEditorSheet = false
        editingBlockId = nil
        selectedBlockId = nil
        layoutStore.setMode(next)
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
            guard let firstId = layoutStore.rectangles.first?.id else { return }
            isEditingLayout = true
            editingBlockId = editingBlockId ?? firstId
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
            },
            region: activeRegion,
            cameraKey: cameraKey,
            parcels: planningParcels
        )
        .overlay(alignment: .top) { modeBanner }
        .overlay { emptyPlanningOverlay }
    }

    @ViewBuilder
    private var modeBanner: some View {
        if mode == .planning {
            let name = layoutStore.activeProfile?.name
            let label = name.map { "PLANNING · internal · \($0) · \(blocks.count) blocks" }
                ?? "PLANNING · internal"
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.yellow.opacity(0.92), in: Capsule())
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var emptyPlanningOverlay: some View {
        if mode == .planning, layoutStore.rectangles.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No planning layout yet")
                    .font(.headline)
                Text("Tap the menu and choose “New vineyard” to auto-arrange sensor blocks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showGeneratorSheet = true
                } label: {
                    Label("New vineyard", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
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
