import MapKit
import SwiftUI

/// One sensor node to be positioned on the map.
struct DevicePin: Identifiable, Equatable {
    let id: String          // device id, e.g. "farm_ab-A1"
    let name: String        // display name, e.g. "PB Node A1"
    var coordinate: CLLocationCoordinate2D

    static func == (lhs: DevicePin, rhs: DevicePin) -> Bool {
        lhs.id == rhs.id
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Full-screen satellite map with one draggable marker per device.
///
/// Unlike the demo, which assigned block locations for us, the customer drags each pin to where the
/// node is physically installed. Uses MapKit's built-in annotation dragging (`isDraggable`), which
/// is far more robust than a hand-rolled gesture and gives the standard lift-and-drop feel.
struct DevicePlacementMap: UIViewRepresentable {
    @Binding var pins: [DevicePin]
    let region: MKCoordinateRegion

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        // Hybrid = satellite imagery + road/label overlay, so rows and buildings are visible.
        map.preferredConfiguration = MKHybridMapConfiguration()
        map.setRegion(region, animated: false)
        map.pointOfInterestFilter = .excludingAll
        context.coordinator.sync(map, pins: pins)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.sync(map, pins: pins)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let parent: DevicePlacementMap

        init(_ parent: DevicePlacementMap) { self.parent = parent }

        /// Reconcile annotations with the current pins. Existing markers are left where they are so
        /// we never fight the user mid-drag; only additions/removals are applied.
        func sync(_ map: MKMapView, pins: [DevicePin]) {
            let existing = map.annotations.compactMap { $0 as? DeviceAnnotation }
            let wantedIds = Set(pins.map(\.id))

            for annotation in existing where !wantedIds.contains(annotation.deviceId) {
                map.removeAnnotation(annotation)
            }
            let haveIds = Set(existing.map(\.deviceId))
            for pin in pins where !haveIds.contains(pin.id) {
                map.addAnnotation(DeviceAnnotation(pin: pin))
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let device = annotation as? DeviceAnnotation else { return nil }
            let id = "device-pin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: device, reuseIdentifier: id)
            view.annotation = device
            view.isDraggable = true
            view.canShowCallout = true
            view.animatesWhenAdded = true
            view.markerTintColor = .systemGreen
            view.glyphText = device.shortLabel
            return view
        }

        func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState,
            fromOldState oldState: MKAnnotationView.DragState
        ) {
            guard let device = view.annotation as? DeviceAnnotation else { return }
            switch newState {
            case .ending, .canceling:
                view.dragState = .none
                // Write the dropped position back to the binding.
                if let index = parent.pins.firstIndex(where: { $0.id == device.deviceId }) {
                    parent.pins[index].coordinate = device.coordinate
                }
            default:
                break
            }
        }
    }
}

/// Map annotation backed by a device. `MKPointAnnotation.coordinate` is KVO-compliant and settable,
/// so MapKit updates it live during a drag.
final class DeviceAnnotation: MKPointAnnotation {
    let deviceId: String
    let shortLabel: String

    init(pin: DevicePin) {
        deviceId = pin.id
        shortLabel = DeviceAnnotation.glyph(for: pin.name)
        super.init()
        title = pin.name
        coordinate = pin.coordinate
    }

    /// A short marker glyph like "A1" pulled from "PB Node A1", falling back to the first characters.
    private static func glyph(for name: String) -> String {
        if let match = name.range(of: #"[Aa]\d+"#, options: .regularExpression) {
            return String(name[match]).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
