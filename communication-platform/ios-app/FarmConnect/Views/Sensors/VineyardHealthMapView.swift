import MapKit
import SwiftUI

struct VineyardHealthMapView: View {
    let blocks: [VineyardDemoBlock]
    @Binding var selectedBlockId: String?
    @State private var mapPosition: MapCameraPosition = VineyardDemoData.initialCamera

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MapReader { proxy in
                Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                    ForEach(blocks) { block in
                        MapPolygon(coordinates: block.polygon)
                            .foregroundStyle(block.riskLevel.fillColor.opacity(fillOpacity(for: block)))
                            .stroke(
                                strokeColor(for: block),
                                lineWidth: block.id == selectedBlockId ? 3.5 : 1.5
                            )

                        Annotation(block.name, coordinate: block.center, anchor: .center) {
                            Button {
                                toggleSelection(for: block)
                            } label: {
                                sensorNodeMarker(for: block)
                            }
                            .buttonStyle(.plain)
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
            }

            mapLegend
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
            Text("Tap a block for canopy readings")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
        let isSelected = block.id == selectedBlockId
        return ZStack {
            Circle()
                .fill(block.riskLevel.fillColor)
                .frame(width: isSelected ? 16 : 12, height: isSelected ? 16 : 12)
                .overlay {
                    Circle()
                        .stroke(.white, lineWidth: isSelected ? 2.5 : 1.5)
                }
            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .font(.system(size: isSelected ? 7 : 6))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .accessibilityLabel("\(block.name), \(block.riskLevel.label)")
    }

    private func fillOpacity(for block: VineyardDemoBlock) -> Double {
        block.id == selectedBlockId ? 0.55 : 0.42
    }

    private func strokeColor(for block: VineyardDemoBlock) -> Color {
        block.id == selectedBlockId ? .white : block.riskLevel.strokeColor
    }

    private func toggleSelection(for block: VineyardDemoBlock) {
        selectedBlockId = block.id == selectedBlockId ? nil : block.id
    }

    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard let coordinate = proxy.convert(point, from: .local) else { return }

        if let hit = blocks.first(where: { GeoPolygon.contains(coordinate, polygon: $0.polygon) }) {
            toggleSelection(for: hit)
        } else {
            selectedBlockId = nil
        }
    }
}
