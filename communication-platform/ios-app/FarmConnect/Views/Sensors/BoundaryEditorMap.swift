import MapKit
import SwiftUI

/// Satellite map for editing one or more vine-area parcels:
/// - the ACTIVE parcel is highlighted; tap empty map to append a point to it
/// - drag a corner handle to move it
/// - long-press a corner handle to remove it (minimum 3 points kept per parcel)
/// Other parcels are shown dimmed for context; tap a dimmed parcel's badge to make it active.
struct BoundaryEditorMap: View {
    @Binding var parcels: [[CLLocationCoordinate2D]]
    @Binding var activeParcel: Int
    @Binding var region: MKCoordinateRegion

    @State private var mapPosition: MapCameraPosition
    @State private var dragStartMap: CLLocationCoordinate2D?
    @State private var dragOriginPoint: CLLocationCoordinate2D?

    init(
        parcels: Binding<[[CLLocationCoordinate2D]]>,
        activeParcel: Binding<Int>,
        region: Binding<MKCoordinateRegion>
    ) {
        _parcels = parcels
        _activeParcel = activeParcel
        _region = region
        _mapPosition = State(initialValue: .region(region.wrappedValue))
    }

    private var activeIndex: Int {
        parcels.indices.contains(activeParcel) ? activeParcel : 0
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                ForEach(Array(parcels.enumerated()), id: \.offset) { pIndex, parcel in
                    if parcel.count >= 2 {
                        MapPolygon(coordinates: parcel)
                            .foregroundStyle((pIndex == activeIndex ? Color.yellow : Color.white).opacity(0.16))
                            .stroke(pIndex == activeIndex ? .yellow : .white.opacity(0.7),
                                    lineWidth: pIndex == activeIndex ? 2 : 1.5)
                    }
                }

                // Corner handles for the active parcel only (keeps the map uncluttered).
                if parcels.indices.contains(activeIndex) {
                    ForEach(Array(parcels[activeIndex].enumerated()), id: \.offset) { index, coord in
                        Annotation("", coordinate: coord, anchor: .center) {
                            cornerHandle(index: index, proxy: proxy)
                        }
                    }
                }
            }
            .mapStyle(.imagery)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture(coordinateSpace: .local) { location in
                guard parcels.indices.contains(activeIndex),
                      let coord = proxy.convert(location, from: .local) else { return }
                parcels[activeIndex].append(coord)
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
                guard parcels.indices.contains(activeIndex),
                      parcels[activeIndex].indices.contains(index) else { return }
                if dragStartMap == nil {
                    dragStartMap = proxy.convert(value.startLocation, from: .local)
                    dragOriginPoint = parcels[activeIndex][index]
                }
                guard let start = dragStartMap,
                      let origin = dragOriginPoint,
                      let current = proxy.convert(value.location, from: .local)
                else { return }
                let dLat = current.latitude - start.latitude
                let dLng = current.longitude - start.longitude
                parcels[activeIndex][index] = CLLocationCoordinate2D(
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
        guard parcels.indices.contains(activeIndex) else { return }
        guard parcels[activeIndex].count > 3, parcels[activeIndex].indices.contains(index) else { return }
        parcels[activeIndex].remove(at: index)
    }
}
