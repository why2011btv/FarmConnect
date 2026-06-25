import MapKit
import SwiftUI

/// Auto-arrangement flow (Planning mode): enter a vineyard name -> backend drafts a vine-area
/// boundary on the satellite map -> user taps to fix corners -> blocks are tiled at a chosen
/// density and installed into the planning slot.
struct VineyardGeneratorView: View {
    @ObservedObject var layoutStore: VineyardBlockLayoutStore
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phase: Phase = .input
    @State private var errorMessage: String?

    // Boundary editing
    @State private var boundary: [CLLocationCoordinate2D] = []
    @State private var region = VineyardDemoData.mapRegion
    @State private var source: String?

    // Density
    @State private var acresPerBlock: Double = 10
    @State private var rotationDegrees: Double = 0

    enum Phase: Equatable {
        case input
        case analyzing
        case editing
    }

    private var acreage: Double {
        VineyardLayoutGenerator.geodesicAreaAcres(boundary)
    }

    private var blockCount: Int {
        VineyardLayoutGenerator.recommendedBlockCount(acres: acreage, acresPerBlock: acresPerBlock)
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
                            .disabled(boundary.count < 3)
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
                Text("We look up the vineyard, outline its vine area on satellite imagery, then auto-place sensor coverage blocks. You can fix the outline before generating.")
            }
        }
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Locating \(name) and outlining the vine area…")
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
            BoundaryEditorMap(boundary: $boundary, region: $region)
                .frame(maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if let source {
                    sourceBadge(source)
                }

                HStack {
                    metric(title: "Vine area", value: String(format: "%.1f ac", acreage))
                    Spacer()
                    metric(title: "Coverage blocks", value: "\(blockCount)")
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Density")
                        Spacer()
                        Text(String(format: "1 block / %.0f ac", acresPerBlock))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    Slider(value: $acresPerBlock, in: 2...50, step: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Row alignment")
                        Spacer()
                        Text("\(Int(rotationDegrees))°")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    Slider(value: $rotationDegrees, in: -45...45, step: 1)
                }

                Text("Tap the map to add boundary points; drag a point to move it; long-press a point to remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }

    private func sourceBadge(_ source: String) -> some View {
        let (text, color): (String, Color) = {
            switch source {
            case "osm": return ("Boundary from map data — adjust if needed", .green)
            case "vision": return ("Boundary estimated from satellite — please verify", .orange)
            default: return ("Location only — draw the vine boundary", .secondary)
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
                // Pass 1: name only -> geocoded center (+ OSM boundary if one exists). We can't
                // snapshot the right place until we know where the vineyard is.
                var response = try await APIClient.shared.analyzeVineyard(name: trimmed, snapshot: nil)

                // Pass 2: if no boundary yet, snapshot the satellite imagery AT THE GEOCODED CENTER
                // and let the backend's vision model trace the vine area there.
                if response.boundary.count < 3 {
                    let centeredRegion = regionAround(response.centerCoordinate)
                    if let snapshot = await VineyardMapSnapshot.make(region: centeredRegion) {
                        let visionResponse = try await APIClient.shared.analyzeVineyard(name: trimmed, snapshot: snapshot)
                        if visionResponse.boundary.count >= 3 {
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
        let center = response.centerCoordinate
        let coords = response.boundaryCoordinates

        if coords.count >= 3 {
            boundary = coords
            region = VineyardLayoutGenerator.region(forBoundary: coords) ?? regionAround(center)
        } else {
            // Geocode-only: seed an editable default box so the user always has something to adjust.
            boundary = VineyardLayoutGenerator.defaultBoundaryBox(center: center)
            region = VineyardLayoutGenerator.region(forBoundary: boundary) ?? regionAround(center)
        }
        phase = .editing
    }

    private func regionAround(_ center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.0065, longitudeDelta: 0.0045)
        )
    }

    private func generateAndInstall() {
        let rectangles = VineyardLayoutGenerator.generateBlocks(
            boundary: boundary,
            count: blockCount,
            rotationDegrees: rotationDegrees
        )
        guard !rectangles.isEmpty else {
            errorMessage = "Couldn't place blocks inside that boundary. Try widening it."
            return
        }

        // Frame the saved layout to the final (possibly edited) boundary, not the initial camera.
        let framed = VineyardLayoutGenerator.region(forBoundary: boundary) ?? region
        let profile = VineyardProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            centerLatitude: framed.center.latitude,
            centerLongitude: framed.center.longitude,
            latitudeDelta: framed.span.latitudeDelta,
            longitudeDelta: framed.span.longitudeDelta,
            boundary: boundary.map(Coordinate2D.init),
            acreage: acreage,
            source: source
        )
        layoutStore.installPlanningLayout(rectangles: rectangles, profile: profile)
        onDone?()
        dismiss()
    }
}
