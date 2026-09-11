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
    @State private var showSensorStatus = false
    @State private var showDiseaseRisk = false
    @State private var showHarvestLog = false
    @State private var showRenameVineyard = false
    @State private var vineyardNameDraft = ""
    /// True when the two-pane wide layout is active (kept in sync with the GeometryReader). The
    /// block-detail bottom sheet is a phone-only affordance, so it presents only when this is false.
    @State private var isWide = false

    private var mode: LayoutMode { layoutStore.mode }
    private var layoutStorageScope: String {
        "\(session.currentUser?.id ?? "signed-out")|\(session.farms.first?.id ?? "no-farm")"
    }

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
            .navigationTitle(vineyardNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) { sensorLoadBanner }
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { dashboardToolbar }
            .task(id: cameraKey) {
                await reloadDashboard()
            }
            .task(id: layoutStorageScope) {
                guard let userId = session.currentUser?.id else { return }
                if !session.isAdmin && session.farms.first == nil { return }
                await layoutStore.configure(userId: userId, farmId: session.farms.first?.id)
                // Customers always enter their own farm-scoped planning layout.
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
            .sheet(isPresented: $showHarvestLog) {
                if let farmId = session.farms.first?.id {
                    HarvestLogView(farmId: farmId)
                }
            }
            .sheet(isPresented: $showDiseaseRisk) {
                if let center = layoutStore.activeProfile?.center {
                    DiseaseRiskView(latitude: center.latitude, longitude: center.longitude)
                }
            }
            .sheet(isPresented: $showSensorStatus) {
                SensorStatusView(
                    vineyardName: vineyardNavigationTitle,
                    blocks: blocks,
                    isLoading: sensorViewModel.isLoading || weatherViewModel.isLoading
                )
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
            .alert("Vineyard name", isPresented: $showRenameVineyard) {
                TextField("Vineyard name", text: $vineyardNameDraft)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    layoutStore.renamePlanningVineyard(to: vineyardNameDraft)
                }
                .disabled(vineyardNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("This name is shared with everyone who has access to this vineyard.")
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

    private var vineyardNavigationTitle: String {
        if mode == .planning, let name = layoutStore.activeProfile?.name, !name.isEmpty {
            return name
        }
        return "Vineyard Sensors"
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
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
        ToolbarItem(placement: .topBarTrailing) {
            trailingMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            AccountMenuButton()
        }
    }

    @ViewBuilder
    private var trailingMenu: some View {
        switch mode {
        case .planning:
            Menu {
                Button {
                    showSensorStatus = true
                } label: {
                    Label("Sensor status", systemImage: "sensor.tag.radiowaves.forward")
                }
                .disabled(blocks.isEmpty)
                if layoutStore.activeProfile?.center != nil {
                    Button {
                        showDiseaseRisk = true
                    } label: {
                        Label("Disease risk", systemImage: "leaf.arrow.triangle.circlepath")
                    }
                }
                if layoutStore.activeProfile != nil {
                    Button {
                        vineyardNameDraft = layoutStore.activeProfile?.name ?? ""
                        showRenameVineyard = true
                    } label: {
                        Label("Rename vineyard…", systemImage: "pencil")
                    }
                }
                Button {
                    showGeneratorSheet = true
                } label: {
                    Label("New vineyard…", systemImage: "plus.viewfinder")
                }
                Button {
                    showHarvestLog = true
                } label: {
                    Label("Harvest log", systemImage: "drop.degreesign")
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
                    showSensorStatus = true
                } label: {
                    Label("Sensor status", systemImage: "sensor.tag.radiowaves.forward")
                }
                .disabled(blocks.isEmpty)
                if layoutStore.activeProfile?.center != nil {
                    Button {
                        showDiseaseRisk = true
                    } label: {
                        Label("Disease risk", systemImage: "leaf.arrow.triangle.circlepath")
                    }
                }
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

                // Block-specific disease risk, driven by this block's own device readings.
                BlockDiseaseRiskView(
                    latitude: block.center.latitude,
                    longitude: block.center.longitude,
                    deviceId: block.liveSensor?.deviceId
                )
                .frame(maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Vineyard-wide sensor status (phone menu)

private struct SensorStatusView: View {
    @Environment(\.dismiss) private var dismiss

    let vineyardName: String
    let blocks: [VineyardDemoBlock]
    let isLoading: Bool

    private var goodCount: Int { blocks.filter { $0.riskLevel == .low }.count }
    private var watchCount: Int { blocks.filter { $0.riskLevel == .moderate }.count }
    private var attentionCount: Int { blocks.filter { $0.riskLevel == .high }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        conditionCount(goodCount, label: "Good", color: .green)
                        conditionCount(watchCount, label: "Watch", color: .orange)
                        conditionCount(attentionCount, label: "Attention", color: .red)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(vineyardName)
                } footer: {
                    Text("Block condition combines current field-sensor readings with available local weather.")
                }

                Section("Blocks and nodes") {
                    ForEach(blocks) { block in
                        blockRow(block)
                    }
                }
            }
            .overlay {
                if isLoading && blocks.isEmpty {
                    ProgressView("Loading sensor status…")
                }
            }
            .navigationTitle("Sensor status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func conditionCount(_ count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func blockRow(_ block: VineyardDemoBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(block.riskLevel.fillColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.name)
                        .font(.headline)
                    Text(block.locationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(conditionLabel(for: block.riskLevel))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(block.riskLevel.fillColor)
            }

            if let sensor = block.liveSensor {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(sensor.deviceName)
                    Text("· Updated \(sensor.lastSeenAt.formatted(date: .omitted, time: .shortened))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let connection = block.sensorConnection {
                HStack(spacing: 5) {
                    Circle()
                        .fill(connection.isOnline ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(connection.deviceName)
                    Text(connection.isOnline ? "· Online" : "· Offline")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label("Local weather only", systemImage: "cloud.sun")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                metric("Temp", value: temperature(for: block))
                metric("Humidity", value: String(format: "%.1f%%", block.readings.relativeHumidityPct))
                metric("Leaf wetness", value: String(format: "%.1f%%", block.readings.soilMoisturePct))
            }
        }
        .padding(.vertical, 5)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func temperature(for block: VineyardDemoBlock) -> String {
        if let temperatureC = block.liveSensor?.temperatureC {
            return String(format: "%.1f°C", temperatureC)
        }
        return String(format: "%.1f°F", block.readings.airTemperatureF)
    }

    private func conditionLabel(for risk: VineyardRiskLevel) -> String {
        switch risk {
        case .low: return "Good"
        case .moderate: return "Watch"
        case .high: return "Needs attention"
        }
    }
}
