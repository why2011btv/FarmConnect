import MapKit
import SwiftUI

/// Auto-arrangement flow (Planning mode): enter a vineyard name -> backend researches its acreage
/// and drafts the vine-area parcels on the satellite map -> user fixes corners / adds parcels ->
/// blocks are tiled across all parcels at a chosen density and installed into the planning slot.
struct VineyardGeneratorView: View {
    @ObservedObject var layoutStore: VineyardBlockLayoutStore
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phase: Phase = .input
    @State private var errorMessage: String?

    // Parcel editing — a vineyard may be several disjoint blocks.
    @State private var parcels: [[CLLocationCoordinate2D]] = []
    @State private var activeParcel = 0
    @State private var region = VineyardDemoData.mapRegion
    @State private var source: String?

    // Researched acreage (context only; map area drives device count).
    @State private var reportedAcreage: Double?
    @State private var reportedAcreageNote: String?

    // Density
    @State private var acresPerBlock: Double = 10
    @State private var rotationDegrees: Double = 0

    enum Phase: Equatable {
        case input
        case analyzing
        case editing
    }

    /// Measured acreage across all parcels — drives device count.
    private var acreage: Double {
        VineyardLayoutGenerator.totalAcres(parcels)
    }

    private var blockCount: Int {
        VineyardLayoutGenerator.recommendedBlockCount(acres: acreage, acresPerBlock: acresPerBlock)
    }

    private var canGenerate: Bool {
        parcels.contains { $0.count >= 3 }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:
                    inputForm
                case .analyzing:
                    analyzingView
                case .editing:
                    editingView
                }
            }
            .navigationTitle("New vineyard")
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
            .alert("Couldn't analyze vineyard", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Input

    private var inputForm: some View {
        Form {
            Section("Vineyard name") {
                TextField("e.g. Running Brook Vineyards, Dartmouth MA", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit { analyze() }
            }
            Section {
                Button {
                    analyze()
                } label: {
                    Label("Analyze on satellite map", systemImage: "scope")
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("We research the vineyard's acreage, outline its vine parcels on satellite imagery, then auto-place sensor coverage blocks. You can fix the outline and add parcels before generating.")
            }
        }
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Researching \(name) and outlining its vine parcels…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                    densityControls

                    Text("Tap the map to add a point to the active parcel; drag a point to move it; long-press to remove it. Use “Add parcel” for a separate vineyard block.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)

                if parcels.count > 1 {
                    Button(role: .destructive) {
                        removeActiveParcel()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
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
                    Text(reportedAcreageNote ?? "unverified")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                }
            }
            Spacer()
            metric(title: "Coverage blocks", value: "\(blockCount)")
        }
    }

    @ViewBuilder
    private var densityControls: some View {
        if acreageDisagrees, let reportedAcreage {
            Label("Mapped area differs from the reported \(String(format: "%.0f", reportedAcreage)) ac. Device count uses the mapped area — add or resize parcels if some vine blocks are missing.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Density")
                Spacer()
                Text(String(format: "1 block / %.0f ac", acresPerBlock))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: $acresPerBlock, in: 2...50, step: 1)
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
            .font(.caption)
            .foregroundStyle(color)
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

    private func analyze() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        phase = .analyzing

        Task {
            do {
                // Pass 1: name only -> geocoded center, OSM parcels (if any), researched acreage.
                var response = try await APIClient.shared.analyzeVineyard(name: trimmed, snapshot: nil)

                // Pass 2: if no parcels yet, snapshot satellite imagery AT THE GEOCODED CENTER and
                // let the backend's vision model trace the vine area there.
                if response.parcels.isEmpty {
                    let centeredRegion = regionAround(response.centerCoordinate)
                    if let snapshot = await VineyardMapSnapshot.make(region: centeredRegion) {
                        let visionResponse = try await APIClient.shared.analyzeVineyard(name: trimmed, snapshot: snapshot)
                        if !visionResponse.parcels.isEmpty {
                            response = visionResponse
                        }
                    }
                }

                await MainActor.run { applyAnalysis(response) }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    phase = .input
                }
            }
        }
    }

    private func applyAnalysis(_ response: VineyardAnalyzeResponse) {
        source = response.source
        reportedAcreage = response.reportedAcreage
        reportedAcreageNote = response.reportedAcreageNote
        let center = response.centerCoordinate
        let parcelCoords = response.parcelCoordinates.filter { $0.count >= 3 }

        if !parcelCoords.isEmpty {
            parcels = parcelCoords
            region = VineyardLayoutGenerator.region(forParcels: parcelCoords) ?? regionAround(center)
        } else {
            // Geocode-only: seed an editable default box so the user always has something to adjust.
            // Size it to the reported acreage when we have one.
            let box = VineyardLayoutGenerator.defaultBoundaryBox(center: center, acres: response.reportedAcreage ?? 20)
            parcels = [box]
            region = VineyardLayoutGenerator.region(forParcels: parcels) ?? regionAround(center)
        }
        activeParcel = 0
        phase = .editing
    }

    private func regionAround(_ center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.0065, longitudeDelta: 0.0045)
        )
    }

    private func addParcel() {
        // Seed a small box at the current map center so the user can drag it into place.
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
            totalCount: blockCount,
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
            reportedAcreageNote: reportedAcreageNote,
            source: source
        )
        layoutStore.installPlanningLayout(rectangles: rectangles, profile: profile)
        onDone?()
        dismiss()
    }
}
