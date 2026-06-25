import MapKit
import SwiftUI

/// Satellite map for editing a vine-area boundary polygon:
/// - tap empty map to append a boundary point
/// - drag a corner handle to move it
/// - long-press a corner handle to remove it (minimum 3 points kept)
struct BoundaryEditorMap: View {
    @Binding var boundary: [CLLocationCoordinate2D]
    @Binding var region: MKCoordinateRegion

    @State private var mapPosition: MapCameraPosition
    @State private var dragStartMap: CLLocationCoordinate2D?
    @State private var dragOriginPoint: CLLocationCoordinate2D?

    init(boundary: Binding<[CLLocationCoordinate2D]>, region: Binding<MKCoordinateRegion>) {
        _boundary = boundary
        _region = region
        _mapPosition = State(initialValue: .region(region.wrappedValue))
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                if boundary.count >= 2 {
                    MapPolygon(coordinates: boundary)
                        .foregroundStyle(.yellow.opacity(0.18))
                        .stroke(.yellow, lineWidth: 2)
                }

                ForEach(Array(boundary.enumerated()), id: \.offset) { index, coord in
                    Annotation("", coordinate: coord, anchor: .center) {
                        cornerHandle(index: index, proxy: proxy)
                    }
                }
            }
            .mapStyle(.imagery)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture(coordinateSpace: .local) { location in
                if let coord = proxy.convert(location, from: .local) {
                    boundary.append(coord)
                }
            }
        }
    }

    private func cornerHandle(index: Int, proxy: MapProxy) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay(
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            // Long-press to delete takes priority; only a deliberate drag (>=10pt) moves the point,
            // so a hold-in-place reliably triggers deletion instead of a 1pt drag.
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in removePoint(at: index) }
            )
            .gesture(dragGesture(index: index, proxy: proxy))
    }

    private func dragGesture(index: Int, proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard boundary.indices.contains(index) else { return }
                if dragStartMap == nil {
                    dragStartMap = proxy.convert(value.startLocation, from: .local)
                    dragOriginPoint = boundary[index]
                }
                guard let start = dragStartMap,
                      let origin = dragOriginPoint,
                      let current = proxy.convert(value.location, from: .local)
                else { return }
                let dLat = current.latitude - start.latitude
                let dLng = current.longitude - start.longitude
                boundary[index] = CLLocationCoordinate2D(
                    latitude: origin.latitude + dLat,
                    longitude: origin.longitude + dLng
                )
            }
            .onEnded { _ in
                dragStartMap = nil
                dragOriginPoint = nil
            }
    }

    private func removePoint(at index: Int) {
        guard boundary.count > 3, boundary.indices.contains(index) else { return }
        boundary.remove(at: index)
    }
}
