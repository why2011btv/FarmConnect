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
    let boundary: [LatLng]
    /// "osm" | "vision" | "geocode-only"
    let source: String
    let note: String?

    var centerCoordinate: CLLocationCoordinate2D { center.coordinate }
    var boundaryCoordinates: [CLLocationCoordinate2D] { boundary.map(\.coordinate) }
}
