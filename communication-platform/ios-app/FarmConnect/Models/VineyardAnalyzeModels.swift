import CoreLocation
import Foundation

/// Request body for `POST /v1/vineyard/analyze`.
struct VineyardAnalyzeRequest: Encodable {
    let name: String
    let snapshot: Snapshot?

    struct Snapshot: Encodable {
        let imageDataUrl: String
        let region: Region
    }

    struct Region: Encodable {
        let centerLat: Double
        let centerLng: Double
        let latDelta: Double
        let lngDelta: Double
    }
}

/// A `{ lat, lng }` pair as returned by the backend.
struct LatLng: Codable, Equatable {
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// Response from `POST /v1/vineyard/analyze`.
struct VineyardAnalyzeResponse: Decodable {
    let center: LatLng
    /// Vine-area parcels (a vineyard is often several disjoint blocks). May be empty.
    let parcels: [[LatLng]]
    /// Acreage measured from `parcels` (drives device count).
    let measuredAcreage: Double
    /// Acreage reported by LLM research, unverified (context only).
    let reportedAcreage: Double?
    let reportedAcreageNote: String?
    /// "osm" | "vision" | "geocode-only"
    let source: String
    let note: String?

    var centerCoordinate: CLLocationCoordinate2D { center.coordinate }
    var parcelCoordinates: [[CLLocationCoordinate2D]] {
        parcels.map { $0.map(\.coordinate) }
    }
}
