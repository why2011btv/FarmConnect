import CoreLocation
import Foundation

/// Axis-aligned rectangle on the map (north–south × east–west half spans).
struct VineyardBlockRectangle: Codable, Identifiable, Equatable {
    let id: String
    var centerLatitude: Double
    var centerLongitude: Double
    /// Half of the north–south extent (degrees latitude).
    var halfLatitudeSpan: Double
    /// Half of the east–west extent (degrees longitude).
    var halfLongitudeSpan: Double

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    /// Polygon vertices: NW, NE, SE, SW.
    var polygon: [CLLocationCoordinate2D] {
        let latN = centerLatitude + halfLatitudeSpan
        let latS = centerLatitude - halfLatitudeSpan
        let lngW = centerLongitude - halfLongitudeSpan
        let lngE = centerLongitude + halfLongitudeSpan
        return [
            CLLocationCoordinate2D(latitude: latN, longitude: lngW),
            CLLocationCoordinate2D(latitude: latN, longitude: lngE),
            CLLocationCoordinate2D(latitude: latS, longitude: lngE),
            CLLocationCoordinate2D(latitude: latS, longitude: lngW),
        ]
    }

    mutating func nudge(latitude deltaLat: Double, longitude deltaLng: Double) {
        centerLatitude += deltaLat
        centerLongitude += deltaLng
    }

    mutating func growLatitude(by delta: Double) {
        halfLatitudeSpan = max(0.00003, halfLatitudeSpan + delta)
    }

    mutating func growLongitude(by delta: Double) {
        halfLongitudeSpan = max(0.00003, halfLongitudeSpan + delta)
    }
}
