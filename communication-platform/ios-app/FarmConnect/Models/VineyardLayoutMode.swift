import CoreLocation
import Foundation
import MapKit

/// Which layout the Sensors tab is showing.
/// - `demo`: curated, farmer-facing layout (the hand-tuned Running Brook blocks). Launch default.
/// - `planning`: auto-arranged layout used internally to judge a proposed device deployment.
enum LayoutMode: String, Codable, CaseIterable, Identifiable {
    case demo
    case planning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: return "Demo"
        case .planning: return "Planning"
        }
    }
}

/// Codable latitude/longitude pair (CLLocationCoordinate2D is not Codable).
struct Coordinate2D: Codable, Equatable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Provenance + camera framing for an auto-generated vineyard layout.
/// `nil` on the curated demo slot, which uses `VineyardDemoData.mapRegion`.
struct VineyardProfile: Codable, Equatable {
    var name: String
    var centerLatitude: Double
    var centerLongitude: Double
    var latitudeDelta: Double
    var longitudeDelta: Double
    /// Editable vine-area parcels the blocks were tiled into (a vineyard may be several disjoint
    /// blocks). Used for re-editing corners and re-rendering the outline.
    var parcels: [[Coordinate2D]]?
    /// Acreage measured from `parcels` (drives device count).
    var acreage: Double?
    /// Acreage reported by LLM research, unverified (shown as context).
    var reportedAcreage: Double?
    var reportedAcreageNote: String?
    /// "osm" | "vision" | "geocode-only"
    var source: String?

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta > 0 ? latitudeDelta : 0.0065,
                longitudeDelta: longitudeDelta > 0 ? longitudeDelta : 0.0045
            )
        )
    }

    /// Parcels as map coordinates (each inner array is one parcel's vertices).
    var parcelCoordinates: [[CLLocationCoordinate2D]] {
        (parcels ?? []).map { $0.map(\.clCoordinate) }
    }
}

/// One self-contained, copyable arrangement: the blocks, their per-block settings,
/// and (for auto-generated layouts) the vineyard profile. This is the unit we persist and reset.
struct LayoutSlot: Codable, Equatable {
    var rectangles: [VineyardBlockRectangle]
    var blockSettings: [String: VineyardBlockSettings]
    var profile: VineyardProfile?

    static let empty = LayoutSlot(rectangles: [], blockSettings: [:], profile: nil)

    init(
        rectangles: [VineyardBlockRectangle],
        blockSettings: [String: VineyardBlockSettings],
        profile: VineyardProfile? = nil
    ) {
        self.rectangles = rectangles
        self.blockSettings = blockSettings
        self.profile = profile
    }
}

/// Holds both layout slots. Both ALWAYS exist (value type, no dictionary, no force-unwrap),
/// so a write to one slot is structurally incapable of touching the other.
struct LayoutSlots {
    var demo: LayoutSlot
    var planning: LayoutSlot

    subscript(_ mode: LayoutMode) -> LayoutSlot {
        get {
            switch mode {
            case .demo: return demo
            case .planning: return planning
            }
        }
        set {
            switch mode {
            case .demo: demo = newValue
            case .planning: planning = newValue
            }
        }
    }
}
