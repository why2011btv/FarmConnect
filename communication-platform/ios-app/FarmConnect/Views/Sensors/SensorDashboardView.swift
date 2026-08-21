import MapKit
import SwiftUI

struct SensorDashboardView: View {
    @EnvironmentObject private var sensorViewModel: SensorViewModel
    @EnvironmentObject private var session: SessionStore

    @StateObject private var layoutStore = VineyardBlockLayoutStore()
    @StateObject private var weatherViewModel = BlockWeatherViewModel()
    @State private var selectedBlockId: String?
    @State private var editingBlockId: String?
    @State private var isEditingLayout = false
    @State private var showLayoutEditorSheet = false
    @State private var showGeneratorSheet = false
    @State private var showDevicePlacement = false
    @State private var showDiseaseRisk = false
    /// True when the two-pane wide layout is active (kept in sync with the GeometryReader). The
    /// block-detail bottom sheet is a phone-only affordance, so it presents only when this is false.
    @State private var isWide = false

    private var mode: LayoutMode { layoutStore.mode }

    /// The customer has redeemed a code but not drawn their vineyard. Their sensors still have to
    /// be visible, so we show a list instead of an empty map.
    private var needsVineyardSetup: Bool {
        mode == .planning && layoutStore.rectangles.isEmpty
    }

    private var nodeList: some View {
        SensorNodeListView(
            devices: sensorViewModel.devices,
            insights: sensorViewModel.insights,
            isLoading: sensorViewModel.isLoading,
            onSetUpVineyard: { showDevicePlacement = true }
        )
    }

    private var blocks: [VineyardDemoBlock] {
        BlockReadingsComposer.compose(
            blocks: layoutStore.blocks,
            weatherByBlockId: weatherViewModel.readingsByBlockId,
            devices: sensorViewModel.devices
        )
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

                    Group {
                        if wide {
                            wideLayout
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else {
                            phoneLayout
                        }
                    }
                    .onAppear { isWide = wide }
                    .onChange(of: wide) { _, newValue in isWide = newValue }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Vineyard Sensors")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) { sensorLoadBanner }
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { dashboardToolbar }
            .task(id: cameraKey) {
                await reloadDashboard()
            }
            .task(id: session.isAdmin) {
                // An older build could have persisted .demo. Customers are moved back to their
                // own vineyard; only staff may sit in the sample layout.
                if !session.isAdmin, layoutStore.mode == .demo {
                    layoutStore.setMode(.planning)
                }
            }
            .refreshable {
                weatherViewModel.invalidate()
                await reloadDashboard()
            }
            .onChange(of: layoutStore.mode) { _, _ in
                weatherViewModel.invalidate()
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
            .sheet(isPresented: $showDiseaseRisk) {
                if let center = layoutStore.activeProfile?.center {
                    DiseaseRiskView(latitude: center.latitude, longitude: center.longitude)
                }
            }
            .sheet(isPresented: $showDevicePlacement) {
                DevicePlacementView(
                    layoutStore: layoutStore,
                    devices: sensorViewModel.devices,
                    onDone: {
                        selectedBlockId = nil
                        Task { await reloadDashboard() }
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
            .sheet(isPresented: showBlockDetailBinding) {
                blockDetailSheet
            }
        }
    }

    // MARK: - Block detail sheet (phone: full-screen map -> tap a block)

    /// Present the detail sheet only in the non-wide (single-column map) layout, when a block is
    /// selected and no other sheet / inline editor owns the screen. Gated on the SAME geometry
    /// predicate that picks phoneLayout, so the wide two-pane layout shows detail inline instead.
    private var showBlockDetailBinding: Binding<Bool> {
        Binding(
            get: {
                !isWide
                    && !isEditingLayout
                    && !showLayoutEditorSheet
                    && !showGeneratorSheet
                    && selectedBlockId != nil
            },
            set: { presented in
                if !presented { selectedBlockId = nil }
            }
        )
    }

    @ViewBuilder
    private var blockDetailSheet: some View {
        if let selectedBlock {
            BlockDetailSheet(
                block: selectedBlock,
                insights: selectedBlock.insights,
                isLoadingWeather: weatherViewModel.isLoading
            )
            .presentationDetents([.fraction(0.45), .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var sensorLoadBanner: some View {
        if sensorViewModel.isLoading || weatherViewModel.isLoading,
           sensorViewModel.devices.isEmpty, weatherViewModel.readingsByBlockId.isEmpty {
            Text("Loading vineyard data…")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 4)
        } else if let error = sensorViewModel.errorMessage ?? weatherViewModel.errorMessage {
            Text(error)
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 4)
        }
    }

    private func reloadDashboard() async {
        let baseBlocks = layoutStore.blocks
        async let sensors: Void = sensorViewModel.load()
        async let weather: Void = weatherViewModel.load(for: baseBlocks)
        _ = await (sensors, weather)
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            AccountMenuButton()
        }
        // The sample layout is a sales tool. Customers get one view -- their own vineyard --
        // so the picker only exists for staff.
        if session.isAdmin {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: modeBinding) {
                    ForEach(LayoutMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        }
        if layoutStore.activeProfile?.center != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDiseaseRisk = true
                } label: {
                    Image(systemName: "leaf.arrow.triangle.circlepath")
                }
                .accessibilityLabel("Disease risk")
            }
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
                if !layoutStore.rectangles.isEmpty, session.isAdmin {
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
            // The inline sidebar editor only exists inside the wide two-pane layout; in any non-wide
            // geometry (iPhone, or iPad portrait) present the editor as a sheet instead.
            if !isWide {
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
    }

    @ViewBuilder
    private var modeBanner: some View {
        if mode == .demo, session.isAdmin {
            Text("DEMO · sample vineyard · not your data")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.yellow.opacity(0.92), in: Capsule())
                .padding(.top, 8)
        }
    }

    // MARK: - iPad landscape / wide

    @ViewBuilder
    private var wideLayout: some View {
        if needsVineyardSetup {
            nodeList
        } else {
            wideMapLayout
        }
    }

    private var wideMapLayout: some View {
        HStack(spacing: 0) {
            mapView()
                .frame(maxWidth: .infinity)

            Divider()

            // We're inside the wide two-pane layout, so the inline sidebar editor is the right
            // surface here (gate on the same geometry predicate that selected this layout).
            if isEditingLayout {
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
                CanopySensorReadingsView(
                    block: selectedBlock,
                    allBlocks: blocks,
                    layout: .regular,
                    isLoadingWeather: weatherViewModel.isLoading
                )
                    .frame(height: topHeight)

                Divider()

                VineyardInsightsPanel(block: selectedBlock, insights: activeInsights)
                    .frame(height: geo.size.height - topHeight)
            }
        }
    }

    // MARK: - iPhone / portrait

    // Full-screen map; tapping a block raises the detail bottom sheet (see blockDetailSheet).
    @ViewBuilder
    private var phoneLayout: some View {
        if needsVineyardSetup {
            nodeList
        } else {
            mapView()
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

// MARK: - Golden ratio (φ ≈ 1.618): readings ≈ 38.2%, insights ≈ 61.8%
private enum PanelProportions {
    private static let phi: CGFloat = (1 + sqrt(5)) / 2
    static let readings: CGFloat = 1 / (1 + phi)
}

// MARK: - Block detail bottom sheet (phone: full-screen map -> tap a block)

/// Bottom-sheet detail for a tapped vineyard block on the full-screen phone map.
/// Shows the block's canopy readings (metric grid) and its insights / spray recommendations.
/// Reuses the existing panels so it stays in sync with the dashboard's other layouts.
/// (Kept in this file rather than its own to avoid a new Xcode target-membership entry.)
private struct BlockDetailSheet: View {
    let block: VineyardDemoBlock
    let insights: [VineyardBlockInsight]
    var isLoadingWeather: Bool = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Readings on top (compact = 2-col grid that scrolls internally if tall), capped so
                // it can't crowd out the insights; insights fill the remainder with their own scroll.
                CanopySensorReadingsView(
                    block: block,
                    layout: .compact,
                    isLoadingWeather: isLoadingWeather
                )
                .frame(maxHeight: geo.size.height * 0.55)

                Divider()

                VineyardInsightsPanel(block: block, insights: insights)
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
