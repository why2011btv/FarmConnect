import MapKit
import SwiftUI

/// Auto-arrangement flow (Planning mode):
///   input -> search (name) -> pick a location candidate (with a researched info card)
///   -> analyze the chosen spot -> edit parcels -> tile blocks -> install into the planning slot.
struct VineyardGeneratorView: View {
    @ObservedObject var layoutStore: VineyardBlockLayoutStore
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phase: Phase = .input
    @State private var errorMessage: String?

    // Search results
    @State private var candidates: [PlaceCandidate] = []
    @State private var research: VineyardResearch?

    // Parcel editing — a vineyard may be several disjoint blocks.
    @State private var parcels: [[CLLocationCoordinate2D]] = []
    @State private var activeParcel = 0
    @State private var region = VineyardDemoData.mapRegion
    @State private var source: String?

    // Placement: the user chooses how many devices (sensor nodes) to place. Each block holds one.
    @State private var deviceCount: Int = 8
    @State private var deviceCountInitialized = false
    @State private var rotationDegrees: Double = 0

    /// How many acres one device is assumed to cover when suggesting a starting count.
    private let recommendedAcresPerDevice: Double = 10
    private let deviceCountRange = 1...64

    enum Phase: Equatable {
        case input
        case searching
        case picking
        case analyzing
        case editing
    }

    /// Measured acreage across all parcels — drives device count.
    private var acreage: Double {
        VineyardLayoutGenerator.totalAcres(parcels)
    }

    /// Suggested device count from the mapped acreage. The user can override it freely.
    private var recommendedCount: Int {
        let rec = VineyardLayoutGenerator.recommendedBlockCount(acres: acreage, acresPerBlock: recommendedAcresPerDevice)
        return min(max(rec, deviceCountRange.lowerBound), deviceCountRange.upperBound)
    }

    /// Seed the device count from the recommendation the first time we reach the editing step,
    /// then leave it under the user's control.
    private func initializeDeviceCountIfNeeded() {
        guard !deviceCountInitialized else { return }
        deviceCount = recommendedCount
        deviceCountInitialized = true
    }

    private var canGenerate: Bool {
        parcels.contains { $0.count >= 3 }
    }

    private var reportedAcreage: Double? { research?.reportedAcreage }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input: inputForm
                case .searching: progressView("Searching for \(name)…")
                case .picking: pickingView
                case .analyzing: progressView("Outlining the vine parcels…")
                case .editing: editingView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if phase == .editing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Generate") { generateAndInstall() }
                            .disabled(!canGenerate)
                    }
                }
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var navigationTitle: String {
        switch phase {
        case .input, .searching: return "New vineyard"
        case .picking: return "Pick location"
        case .analyzing, .editing: return "Outline & generate"
        }
    }

    private func progressView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Input

    private var inputForm: some View {
        Form {
            Section("Vineyard name") {
                TextField("Vineyard name and town", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit { search() }
            }
            Section {
                Button {
                    search()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("We look up the vineyard, show what we find about it, and let you pick the right spot on the map. Then we outline its vine parcels and auto-place sensor coverage blocks.")
            }
        }
    }

    // MARK: - Picking (research card + candidate list)

    private var pickingView: some View {
        List {
            if let research {
                Section("About this vineyard") {
                    researchCard(research)
                }
            }

            Section(candidates.isEmpty ? "No locations found" : "Pick the correct location") {
                if candidates.isEmpty {
                    Text("We couldn't find a mapped location for that name. Try a more specific name (add the town or region), then search again.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        phase = .input
                    } label: {
                        Label("Search again", systemImage: "magnifyingglass")
                    }
                } else {
                    ForEach(candidates) { candidate in
                        Button {
                            choose(candidate)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if let kind = candidate.kind {
                                    Text(kind)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func researchCard(_ r: VineyardResearch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = r.summary {
                Text(summary).font(.subheadline)
            }
            researchRow("Reported acreage", value: r.reportedAcreage.map { String(format: "%.0f acres", $0) }, note: r.acreageNote)
            researchRow("Grapes", value: r.grapeVarieties?.joined(separator: ", "))
            researchRow("Ownership", value: r.ownership)
            researchRow("Founded", value: r.founded)
            researchRow("Region", value: r.region)
            researchRow("Address", value: r.address)
            if let site = r.officialWebsite, let url = websiteURL(site) {
                HStack(alignment: .top) {
                    Text("Website").font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                    Link(site, destination: url).font(.subheadline)
                }
            }
            Text("Researched info — unverified. Confirm details with the grower.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Normalize a possibly scheme-less website string into a tappable URL.
    private func websiteURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)
    }

    @ViewBuilder
    private func researchRow(_ label: String, value: String?, note: String? = nil) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value).font(.subheadline)
                    if let note, !note.isEmpty {
                        Text(note).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Editing

    private var editingView: some View {
        VStack(spacing: 0) {
            BoundaryEditorMap(parcels: $parcels, activeParcel: $activeParcel, region: $region)
                .frame(maxHeight: .infinity)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let source {
                        sourceBadge(source)
                    }
                    parcelChips
                    acreagePanel
                    placementControls
                    Text("Tap the map to add a point to the active parcel; drag a point to move it; long-press to remove it. Use “Add parcel” for a separate vineyard block.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .frame(maxHeight: 320)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var parcelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(parcels.enumerated()), id: \.offset) { index, parcel in
                    Button {
                        activeParcel = index
                    } label: {
                        Text("Parcel \(index + 1) · \(String(format: "%.1f ac", VineyardLayoutGenerator.geodesicAreaAcres(parcel)))")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(index == activeParcel ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(index == activeParcel ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    addParcel()
                } label: {
                    Label("Add parcel", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)

                if parcels.count > 1 {
                    Button(role: .destructive) {
                        removeActiveParcel()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var acreagePanel: some View {
        HStack(alignment: .top) {
            metric(title: "Mapped area (\(parcels.count) parcel\(parcels.count == 1 ? "" : "s"))",
                   value: String(format: "%.1f ac", acreage))
            Spacer()
            if let reportedAcreage {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Reported").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.1f ac", reportedAcreage))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(acreageDisagrees ? .orange : .primary)
                    if let note = research?.acreageNote {
                        Text(note).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2).multilineTextAlignment(.trailing)
                    }
                }
            }
            Spacer()
            metric(title: "Devices", value: "\(deviceCount)")
        }
    }

    @ViewBuilder
    private var placementControls: some View {
        if acreageDisagrees, let reportedAcreage {
            Label("Mapped area differs from the reported \(String(format: "%.0f", reportedAcreage)) ac. Blocks are spread across the mapped area — add or resize parcels if some vine blocks are missing.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }

        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $deviceCount, in: deviceCountRange) {
                HStack {
                    Text("Devices to place")
                    Spacer()
                    Text("\(deviceCount)")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.subheadline)
            }

            HStack(spacing: 8) {
                // Density is now a consequence of the chosen device count, shown for context.
                if acreage > 0 {
                    Text(String(format: "≈ %.0f ac / device", acreage / Double(max(deviceCount, 1))))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if deviceCount != recommendedCount {
                    Button("Use recommended (\(recommendedCount))") {
                        deviceCount = recommendedCount
                    }
                    .font(.caption)
                }
            }

            Text("Place one block per sensor node you're deploying. Nodes map to blocks in order — node A1 to the first block, A2 to the second, and so on.")
                .font(.caption2).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Row alignment")
                Spacer()
                Text("\(Int(rotationDegrees))°")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: $rotationDegrees, in: -45...45, step: 1)
        }
    }

    /// Flag when measured vs reported acreage differ by more than ~25%.
    private var acreageDisagrees: Bool {
        guard let reportedAcreage, reportedAcreage > 0, acreage > 0 else { return false }
        return abs(acreage - reportedAcreage) / reportedAcreage > 0.25
    }

    private func sourceBadge(_ source: String) -> some View {
        let (text, color): (String, Color) = {
            switch source {
            case "osm": return ("Parcels from map data — adjust if needed", .green)
            case "vision": return ("Area estimated from satellite — please verify", .orange)
            default: return ("Location only — draw the vine parcels", .secondary)
            }
        }()
        return Label(text, systemImage: "info.circle")
            .font(.caption).foregroundStyle(color)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

    // MARK: - Actions

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func search() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        phase = .searching

        Task {
            do {
                let result = try await APIClient.shared.searchVineyard(name: trimmed)
                await MainActor.run {
                    candidates = result.candidates
                    research = result.research
                    phase = .picking
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    phase = .input
                }
            }
        }
    }

    private func choose(_ candidate: PlaceCandidate) {
        phase = .analyzing
        let center = candidate.coordinate
        region = regionAround(center)

        Task {
            do {
                // Pass 1: OSM parcels at the chosen center.
                var response = try await APIClient.shared.analyzeVineyard(
                    center: LatLng(lat: center.latitude, lng: center.longitude),
                    snapshot: nil
                )

                // Pass 2: if no parcels, snapshot satellite imagery at the chosen center and let the
                // backend's vision model trace the vine area there.
                if response.parcels.isEmpty {
                    if let snapshot = await VineyardMapSnapshot.make(region: regionAround(center)) {
                        let visionResponse = try await APIClient.shared.analyzeVineyard(
                            center: LatLng(lat: center.latitude, lng: center.longitude),
                            snapshot: snapshot
                        )
                        if !visionResponse.parcels.isEmpty {
                            response = visionResponse
                        }
                    }
                }

                await MainActor.run { applyAnalysis(response) }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    phase = .picking
                }
            }
        }
    }

    private func applyAnalysis(_ response: VineyardAnalyzeResponse) {
        source = response.source
        let center = response.centerCoordinate
        let parcelCoords = response.parcelCoordinates.filter { $0.count >= 3 }

        if !parcelCoords.isEmpty {
            parcels = parcelCoords
            region = VineyardLayoutGenerator.region(forParcels: parcelCoords) ?? regionAround(center)
            activeParcel = 0
            initializeDeviceCountIfNeeded()
            phase = .editing
        } else {
            applyGeocodeOnly(center: center)
        }
    }

    private func applyGeocodeOnly(center: CLLocationCoordinate2D) {
        source = "geocode-only"
        let box = VineyardLayoutGenerator.defaultBoundaryBox(center: center, acres: reportedAcreage ?? 20)
        parcels = [box]
        region = VineyardLayoutGenerator.region(forParcels: parcels) ?? regionAround(center)
        activeParcel = 0
        initializeDeviceCountIfNeeded()
        phase = .editing
    }

    private func regionAround(_ center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.0065, longitudeDelta: 0.0045)
        )
    }

    private func addParcel() {
        let box = VineyardLayoutGenerator.defaultBoundaryBox(center: region.center, acres: 5)
        parcels.append(box)
        activeParcel = parcels.count - 1
    }

    private func removeActiveParcel() {
        guard parcels.count > 1, parcels.indices.contains(activeParcel) else { return }
        parcels.remove(at: activeParcel)
        activeParcel = min(activeParcel, parcels.count - 1)
    }

    private func generateAndInstall() {
        let validParcels = parcels.filter { $0.count >= 3 }
        let rectangles = VineyardLayoutGenerator.generateBlocks(
            parcels: validParcels,
            totalCount: deviceCount,
            rotationDegrees: rotationDegrees
        )
        guard !rectangles.isEmpty else {
            errorMessage = "Couldn't place blocks inside those parcels. Try widening them."
            return
        }

        // Frame the saved layout to the final (possibly edited) parcels, not the initial camera.
        let framed = VineyardLayoutGenerator.region(forParcels: validParcels) ?? region
        let profile = VineyardProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            centerLatitude: framed.center.latitude,
            centerLongitude: framed.center.longitude,
            latitudeDelta: framed.span.latitudeDelta,
            longitudeDelta: framed.span.longitudeDelta,
            parcels: validParcels.map { $0.map(Coordinate2D.init) },
            acreage: acreage,
            reportedAcreage: reportedAcreage,
            reportedAcreageNote: research?.acreageNote,
            source: source
        )
        layoutStore.installPlanningLayout(rectangles: rectangles, profile: profile)
        onDone?()
        dismiss()
    }
}
