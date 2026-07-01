import MapKit
import SwiftUI

struct VineyardHealthMapView: View {
    let blocks: [VineyardDemoBlock]
    @Binding var selectedBlockId: String?
    var isEditingLayout: Bool = false
    @Binding var editingBlockId: String?
    var onMoveBlock: ((String, Double, Double) -> Void)?
    /// Camera framing. Defaults to the bundled Running Brook region.
    var region: MKCoordinateRegion = VineyardDemoData.mapRegion
    /// Changing this value retargets the camera to `region` (e.g. on a mode/vineyard switch),
    /// without tearing down the map (avoids dropping the user's pan/zoom mid-demo).
    var cameraKey: String = "default"
    /// Optional read-only vine-area parcel outlines (shown in Planning mode).
    var parcels: [[CLLocationCoordinate2D]] = []

    @State private var mapPosition = MapCameraPosition.region(VineyardDemoData.mapRegion)
    @State private var dragMapStart: CLLocationCoordinate2D?
    @State private var dragOriginCenter: CLLocationCoordinate2D?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MapReader { proxy in
                Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                    ForEach(Array(parcels.enumerated()), id: \.offset) { _, parcel in
                        if parcel.count >= 3 {
                            MapPolygon(coordinates: parcel)
                                .foregroundStyle(.clear)
                                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        }
                    }

                    ForEach(blocks) { block in
                        MapPolygon(coordinates: block.polygon)
                            .foregroundStyle(block.riskLevel.fillColor.opacity(fillOpacity(for: block)))
                            .stroke(
                                strokeColor(for: block),
                                lineWidth: isHighlighted(block) ? 3.5 : 1.5
                            )

                        Annotation(blockLabel(block), coordinate: block.center, anchor: .center) {
                            annotationContent(for: block, proxy: proxy)
                        }
                    }
                }
                .mapStyle(.imagery)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture(coordinateSpace: .local) { location in
                    handleMapTap(at: location, proxy: proxy)
                }
                .onChange(of: cameraKey) { _, _ in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        mapPosition = .region(region)
                    }
                }
                .onAppear {
                    mapPosition = .region(region)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if isEditingLayout {
                    Text("Layout edit mode")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.yellow.opacity(0.9), in: Capsule())
                    Text("Select a block in the editor, then nudge or drag its marker.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                mapLegend
            }
            .padding(12)
        }
    }

    private var mapLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Crop health")
                .font(.caption.weight(.semibold))
            legendRow(color: .green, label: "Low fungus risk")
            legendRow(color: .orange, label: "Moderate risk")
            legendRow(color: .red, label: "High fungus risk")
            if !isEditingLayout {
                Text("Tap a block for canopy readings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func annotationContent(for block: VineyardDemoBlock, proxy: MapProxy) -> some View {
        let marker = sensorNodeMarker(for: block)

        if isEditingLayout, editingBlockId == block.id {
            marker
                .gesture(dragGesture(for: block, proxy: proxy))
        } else if isEditingLayout {
            Button {
                editingBlockId = block.id
            } label: {
                marker
            }
            .buttonStyle(.plain)
        } else {
            Button {
                toggleSelection(for: block)
            } label: {
                marker
            }
            .buttonStyle(.plain)
        }
    }

    private func dragGesture(for block: VineyardDemoBlock, proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard let onMoveBlock else { return }
                if dragMapStart == nil {
                    dragMapStart = proxy.convert(value.startLocation, from: .local)
                    dragOriginCenter = block.center
                }
                guard let mapStart = dragMapStart,
                      let origin = dragOriginCenter,
                      let current = proxy.convert(value.location, from: .local)
                else { return }

                let deltaLat = current.latitude - mapStart.latitude
                let deltaLng = current.longitude - mapStart.longitude
                onMoveBlock(
                    block.id,
                    origin.latitude + deltaLat,
                    origin.longitude + deltaLng
                )
            }
            .onEnded { _ in
                dragMapStart = nil
                dragOriginCenter = nil
            }
    }

    private func blockLabel(_ block: VineyardDemoBlock) -> String {
        if isEditingLayout {
            return block.name
        }
        return block.name
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
        }
    }

    private func sensorNodeMarker(for block: VineyardDemoBlock) -> some View {
        let highlighted = isHighlighted(block)
        let isLive = block.liveSensor != nil
        return ZStack {
            if isLive {
                Circle()
                    .stroke(Color.green, lineWidth: highlighted ? 3 : 2)
                    .frame(width: highlighted ? 24 : 18, height: highlighted ? 24 : 18)
            }
            Circle()
                .fill(block.riskLevel.fillColor)
                .frame(width: highlighted ? 18 : 12, height: highlighted ? 18 : 12)
                .overlay {
                    Circle()
                        .stroke(isEditingLayout && highlighted ? .yellow : .white, lineWidth: highlighted ? 2.5 : 1.5)
                }
            if isEditingLayout {
                Text(blockNumber(block))
                    .font(.system(size: highlighted ? 9 : 7, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(.system(size: highlighted ? 7 : 6))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    private func blockNumber(_ block: VineyardDemoBlock) -> String {
        block.id.replacingOccurrences(of: "b", with: "")
    }

    private func isHighlighted(_ block: VineyardDemoBlock) -> Bool {
        if isEditingLayout {
            return block.id == editingBlockId
        }
        return block.id == selectedBlockId
    }

    private func fillOpacity(for block: VineyardDemoBlock) -> Double {
        isHighlighted(block) ? 0.55 : 0.42
    }

    private func strokeColor(for block: VineyardDemoBlock) -> Color {
        if isEditingLayout, block.id == editingBlockId {
            return .yellow
        }
        if block.id == selectedBlockId {
            return .white
        }
        return block.riskLevel.strokeColor
    }

    private func toggleSelection(for block: VineyardDemoBlock) {
        selectedBlockId = block.id == selectedBlockId ? nil : block.id
    }

    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard let coordinate = proxy.convert(point, from: .local) else { return }

        if let hit = blocks.first(where: { GeoPolygon.contains(coordinate, polygon: $0.polygon) }) {
            if isEditingLayout {
                editingBlockId = hit.id
            } else {
                toggleSelection(for: hit)
            }
        } else if !isEditingLayout {
            selectedBlockId = nil
        }
    }
}
