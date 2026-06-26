import CoreLocation
import Foundation

/// A `{ lat, lng }` pair as returned by the backend.
struct LatLng: Codable, Equatable {
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Step 1: search (name -> candidates + research card)

/// Request body for `POST /v1/vineyard/search`.
struct VineyardSearchRequest: Encodable {
    let name: String
}

/// One location the user can pick from.
struct PlaceCandidate: Decodable, Identifiable {
    let label: String
    let lat: Double
    let lng: Double
    let kind: String?

    var id: String { "\(lat),\(lng)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// Researched, unverified facts about the vineyard (LLM knowledge + website).
struct VineyardResearch: Decodable, Equatable {
    let reportedAcreage: Double?
    let acreageNote: String?
    let grapeVarieties: [String]?
    let ownership: String?
    let founded: String?
    let region: String?
    let summary: String?
    let officialWebsite: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
}

/// Response from `POST /v1/vineyard/search`.
struct VineyardSearchResponse: Decodable {
    let candidates: [PlaceCandidate]
    let research: VineyardResearch?
}

// MARK: - Step 2: analyze (chosen center -> parcels)

/// Request body for `POST /v1/vineyard/analyze`.
struct VineyardAnalyzeRequest: Encodable {
    let center: LatLng
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

/// Response from `POST /v1/vineyard/analyze`.
struct VineyardAnalyzeResponse: Decodable {
    let center: LatLng
    /// Vine-area parcels (a vineyard is often several disjoint blocks). May be empty.
    let parcels: [[LatLng]]
    /// Acreage measured from `parcels` (drives device count).
    let measuredAcreage: Double
    /// "osm" | "vision" | "geocode-only"
    let source: String
    let note: String?

    var centerCoordinate: CLLocationCoordinate2D { center.coordinate }
    var parcelCoordinates: [[CLLocationCoordinate2D]] {
        parcels.map { $0.map(\.coordinate) }
    }
}
