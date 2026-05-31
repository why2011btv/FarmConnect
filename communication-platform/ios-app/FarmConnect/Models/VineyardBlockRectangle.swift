import CoreLocation
import Foundation

/// Rectangle on the map; optional rotation in degrees (clockwise from north).
struct VineyardBlockRectangle: Codable, Identifiable, Equatable {
    let id: String
    var centerLatitude: Double
    var centerLongitude: Double
    /// Half of the north–south extent before rotation (degrees latitude).
    var halfLatitudeSpan: Double
    /// Half of the east–west extent before rotation (degrees longitude).
    var halfLongitudeSpan: Double
    /// Clockwise rotation from north (0 = axis-aligned to lat/lng).
    var rotationDegrees: Double

    enum CodingKeys: String, CodingKey {
        case id, centerLatitude, centerLongitude
        case halfLatitudeSpan, halfLongitudeSpan, rotationDegrees
    }

    init(
        id: String,
        centerLatitude: Double,
        centerLongitude: Double,
        halfLatitudeSpan: Double,
        halfLongitudeSpan: Double,
        rotationDegrees: Double = 0
    ) {
        self.id = id
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.halfLatitudeSpan = halfLatitudeSpan
        self.halfLongitudeSpan = halfLongitudeSpan
        self.rotationDegrees = rotationDegrees
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        centerLatitude = try c.decode(Double.self, forKey: .centerLatitude)
        centerLongitude = try c.decode(Double.self, forKey: .centerLongitude)
        halfLatitudeSpan = try c.decode(Double.self, forKey: .halfLatitudeSpan)
        halfLongitudeSpan = try c.decode(Double.self, forKey: .halfLongitudeSpan)
        rotationDegrees = try c.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }

    /// Polygon vertices in order around the perimeter.
    var polygon: [CLLocationCoordinate2D] {
        let rad = rotationDegrees * .pi / 180
        let cosA = cos(rad)
        let sinA = sin(rad)
        let unitCorners: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        return unitCorners.map { dx, dy in
            let localLng = dx * halfLongitudeSpan
            let localLat = dy * halfLatitudeSpan
            let rotLng = localLng * cosA - localLat * sinA
            let rotLat = localLng * sinA + localLat * cosA
            return CLLocationCoordinate2D(
                latitude: centerLatitude + rotLat,
                longitude: centerLongitude + rotLng
            )
        }
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

    mutating func rotate(by delta: Double) {
        rotationDegrees = (rotationDegrees + delta).truncatingRemainder(dividingBy: 360)
    }
}
