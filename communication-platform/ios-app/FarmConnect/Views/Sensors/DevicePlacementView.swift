import CoreLocation
import MapKit
import SwiftUI

/// Customer onboarding for the map: find the vineyard, then drag each of your devices to where it
/// is actually installed.
///
/// This replaces the demo behaviour (which assigned block locations) and the acreage/parcel tiling
/// flow (which is really a planning tool). A real grower has a known, small set of physical nodes;
/// they should place those exact nodes, not tile abstract coverage blocks.
struct DevicePlacementView: View {
    @ObservedObject var layoutStore: VineyardBlockLayoutStore
    /// The customer's reporting devices — one draggable pin is created per device.
    let devices: [SensorDeviceOverview]
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var phase: Phase = .input
    @State private var candidates: [PlaceCandidate] = []
    @State private var pins: [DevicePin] = []
    @State private var region = VineyardDemoData.mapRegion
    @State private var placedName = ""
    @State private var errorMessage: String?

    enum Phase: Equatable { case input, searching, picking, placing }

    /// Stable A1, A2, … order so a node maps to the block in the matching position.
    private var orderedDevices: [SensorDeviceOverview] {
        devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input: inputForm
                case .searching: progress("Finding “\(query)”…")
                case .picking: pickingList
                case .placing: placingMap
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if phase == .placing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                    }
                }
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var navTitle: String {
        switch phase {
        case .input, .searching: return "Your vineyard"
        case .picking: return "Pick location"
        case .placing: return "Place your devices"
        }
    }

    // MARK: - Input

    private var inputForm: some View {
        Form {
            Section("Where is your vineyard?") {
                TextField("Vineyard name or address", text: $query)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit(search)
            }
            Section {
                Button {
                    search()
                } label: {
                    Label("Find on map", systemImage: "mappin.and.ellipse")
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                Text("We'll center the map on your vineyard. Then you'll drop a pin for each of your \(orderedDevices.count) device\(orderedDevices.count == 1 ? "" : "s") where it's installed.")
            }
        }
    }

    // MARK: - Picking

    private var pickingList: some View {
        List {
            Section(candidates.isEmpty ? "No matches" : "Pick the right spot") {
                if candidates.isEmpty {
                    Text("Couldn't find that. Try adding the town or a full address, then search again.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button { phase = .input } label: {
                        Label("Search again", systemImage: "magnifyingglass")
                    }
                } else {
                    ForEach(candidates) { candidate in
                        Button { choose(candidate) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.label).font(.subheadline).foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if let kind = candidate.kind {
                                    Text(kind).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Placing

    private var placingMap: some View {
        ZStack(alignment: .top) {
            DevicePlacementMap(pins: $pins, region: region)
                .ignoresSafeArea(.container, edges: .bottom)

            Text("Drag each pin to where that device is installed. Tap a pin to see which node it is.")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .shadow(radius: 2, y: 1)
        }
    }

    // MARK: - Actions

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func progress(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        phase = .searching

        Task {
            // Prefer the vineyard search (same as the demo). Fall back to a plain-address geocode so
            // a customer who types a street address still gets a result.
            var found: [PlaceCandidate] = []
            do {
                found = try await APIClient.shared.searchVineyard(name: trimmed).candidates
            } catch {
                // Non-fatal: try the geocoder fallback before surfacing an error.
            }
            if found.isEmpty {
                found = await geocodeAddress(trimmed)
            }
            await MainActor.run {
                candidates = found
                phase = .picking
            }
        }
    }

    /// CLGeocoder fallback for plain addresses, mapped into the same candidate shape.
    private func geocodeAddress(_ address: String) async -> [PlaceCandidate] {
        await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(address) { placemarks, _ in
                let results: [PlaceCandidate] = (placemarks ?? []).compactMap { placemark in
                    guard let loc = placemark.location else { return nil }
                    let label = [placemark.name, placemark.locality, placemark.administrativeArea]
                        .compactMap { $0 }.joined(separator: ", ")
                    return PlaceCandidate(
                        label: label.isEmpty ? address : label,
                        lat: loc.coordinate.latitude,
                        lng: loc.coordinate.longitude,
                        kind: "Address"
                    )
                }
                continuation.resume(returning: results)
            }
        }
    }

    private func choose(_ candidate: PlaceCandidate) {
        placedName = query.trimmingCharacters(in: .whitespaces)
        region = MKCoordinateRegion(
            center: candidate.coordinate,
            // Tight enough to see rows/buildings but wide enough to spread the initial pins.
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )
        pins = initialPins(around: candidate.coordinate)
        phase = .placing
    }

    /// Lay the devices out in a small grid near the center so they don't stack on one point; the
    /// customer then drags each to its true location.
    private func initialPins(around center: CLLocationCoordinate2D) -> [DevicePin] {
        let devicesToPlace = orderedDevices
        guard !devicesToPlace.isEmpty else { return [] }

        let spacing = 0.0004 // ~44 m between starting positions
        let columns = max(1, Int(ceil(Double(devicesToPlace.count).squareRoot())))

        return devicesToPlace.enumerated().map { index, device in
            let row = index / columns
            let col = index % columns
            let dLat = (Double(row) - Double(columns - 1) / 2) * spacing
            let dLng = (Double(col) - Double(columns - 1) / 2) * spacing
            return DevicePin(
                id: device.id,
                name: device.name,
                coordinate: CLLocationCoordinate2D(
                    latitude: center.latitude - dLat,
                    longitude: center.longitude + dLng
                )
            )
        }
    }

    private func save() {
        guard !pins.isEmpty else { dismiss(); return }

        // Each device becomes a small block at its pin. Order matches orderedDevices, so node A1
        // maps to the first block, A2 to the second, and so on (see BlockReadingsComposer).
        let rectangles = pins.enumerated().map { index, pin in
            VineyardBlockRectangle(
                id: "gen-\(index + 1)",
                centerLatitude: pin.coordinate.latitude,
                centerLongitude: pin.coordinate.longitude,
                halfLatitudeSpan: 0.00018,
                halfLongitudeSpan: 0.00022,
                rotationDegrees: 0
            )
        }

        let framed = regionFitting(pins: pins) ?? region
        let profile = VineyardProfile(
            name: placedName.isEmpty ? "My Vineyard" : placedName,
            centerLatitude: framed.center.latitude,
            centerLongitude: framed.center.longitude,
            latitudeDelta: framed.span.latitudeDelta,
            longitudeDelta: framed.span.longitudeDelta,
            parcels: nil,
            acreage: nil,
            reportedAcreage: nil,
            reportedAcreageNote: nil,
            source: "manual"
        )

        layoutStore.installPlanningLayout(rectangles: rectangles, profile: profile)
        onDone?()
        dismiss()
    }

    /// A region that comfortably frames all placed pins.
    private func regionFitting(pins: [DevicePin]) -> MKCoordinateRegion? {
        guard !pins.isEmpty else { return nil }
        let lats = pins.map(\.coordinate.latitude)
        let lngs = pins.map(\.coordinate.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        // Pad the bounds, with a floor so a single pin still gets a sensible zoom.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.0025),
            longitudeDelta: max((maxLng - minLng) * 1.6, 0.0025)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
