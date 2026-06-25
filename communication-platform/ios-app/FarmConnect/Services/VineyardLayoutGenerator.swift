import CoreLocation
import Foundation
import MapKit

/// Pure, UI-free helpers that turn a vine-area boundary + a density rule into a grid of
/// coverage blocks. Auto-arrangement core for Planning mode. All functions are deterministic
/// and unit-testable.
enum VineyardLayoutGenerator {
    static let squareMetersPerAcre = 4046.8564224
    /// Meters per degree of latitude (near-constant). Longitude is scaled by cos(latitude).
    static let metersPerDegreeLatitude = 111_320.0

    static func metersPerDegreeLongitude(atLatitude latitude: Double) -> Double {
        metersPerDegreeLatitude * cos(latitude * .pi / 180)
    }

    // MARK: - Area

    /// Area of a lat/lng polygon in acres, via the shoelace formula on a local
    /// equirectangular projection (accurate for vineyard-scale areas).
    static func geodesicAreaAcres(_ polygon: [CLLocationCoordinate2D]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        let lat0 = polygon.map(\.latitude).reduce(0, +) / Double(polygon.count)
        let mPerLat = metersPerDegreeLatitude
        let mPerLng = metersPerDegreeLongitude(atLatitude: lat0)

        // Project to meters relative to the centroid latitude / first longitude.
        let lng0 = polygon[0].longitude
        let pts = polygon.map { coord in
            (x: (coord.longitude - lng0) * mPerLng, y: (coord.latitude - lat0) * mPerLat)
        }

        var sum = 0.0
        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        let areaM2 = abs(sum) / 2
        return areaM2 / squareMetersPerAcre
    }

    // MARK: - Block count

    /// Recommended number of coverage blocks for a vine area.
    /// `blocks = max(minimumBlocks, ceil(acres / acresPerBlock))`.
    static func recommendedBlockCount(
        acres: Double,
        acresPerBlock: Double,
        minimumBlocks: Int = 2
    ) -> Int {
        guard acres > 0, acresPerBlock > 0 else { return minimumBlocks }
        let byArea = Int(ceil(acres / acresPerBlock))
        return max(minimumBlocks, byArea)
    }

    // MARK: - Block generation

    /// Tile the boundary's bounding box with a near-square grid sized so each cell ≈ the target
    /// per-block area, then keep only the cells whose center lies inside the boundary.
    /// Returns rectangles with ids "gen-1", "gen-2", … and the requested rotation.
    static func generateBlocks(
        boundary: [CLLocationCoordinate2D],
        count: Int,
        rotationDegrees: Double = 0,
        idPrefix: String = "gen"
    ) -> [VineyardBlockRectangle] {
        guard boundary.count >= 3, count >= 1 else { return [] }

        let lats = boundary.map(\.latitude)
        let lngs = boundary.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let midLat = (minLat + maxLat) / 2

        let mPerLat = metersPerDegreeLatitude
        let mPerLng = metersPerDegreeLongitude(atLatitude: midLat)

        let bboxWidthM = (maxLng - minLng) * mPerLng
        let bboxHeightM = (maxLat - minLat) * mPerLat
        guard bboxWidthM > 0, bboxHeightM > 0 else { return [] }

        // Target cell area so that, after clipping the bbox grid to the (smaller) boundary, we
        // end up with roughly `count` cells inside.
        let boundaryAreaM2 = geodesicAreaAcres(boundary) * squareMetersPerAcre
        let targetCellAreaM2 = max(1, boundaryAreaM2 / Double(count))
        let targetCellSideM = sqrt(targetCellAreaM2)

        let cols = max(1, Int((bboxWidthM / targetCellSideM).rounded()))
        let rows = max(1, Int((bboxHeightM / targetCellSideM).rounded()))

        let cellWidthDeg = (maxLng - minLng) / Double(cols)
        let cellHeightDeg = (maxLat - minLat) / Double(rows)

        var inside: [VineyardBlockRectangle] = []
        var allCells: [VineyardBlockRectangle] = []
        var index = 0
        for row in 0..<rows {
            for col in 0..<cols {
                let centerLng = minLng + (Double(col) + 0.5) * cellWidthDeg
                let centerLat = minLat + (Double(row) + 0.5) * cellHeightDeg
                let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng)
                let rect = VineyardBlockRectangle(
                    id: "\(idPrefix)-\(index + 1)",
                    centerLatitude: centerLat,
                    centerLongitude: centerLng,
                    halfLatitudeSpan: cellHeightDeg / 2,
                    halfLongitudeSpan: cellWidthDeg / 2,
                    rotationDegrees: rotationDegrees
                )
                allCells.append(rect)
                if GeoPolygon.contains(center, polygon: boundary) {
                    inside.append(rect)
                }
                index += 1
            }
        }

        // Re-number kept cells so ids are contiguous (gen-1..gen-n).
        let kept = inside.isEmpty ? allCells : inside
        return kept.enumerated().map { offset, rect in
            VineyardBlockRectangle(
                id: "\(idPrefix)-\(offset + 1)",
                centerLatitude: rect.centerLatitude,
                centerLongitude: rect.centerLongitude,
                halfLatitudeSpan: rect.halfLatitudeSpan,
                halfLongitudeSpan: rect.halfLongitudeSpan,
                rotationDegrees: rect.rotationDegrees
            )
        }
    }

    // MARK: - Default / fallback boundary

    /// A square boundary centered on `center` sized to `acres` (default ~20 ac). Used when the
    /// backend only geocoded the name and returned no polygon — gives the user something to edit.
    static func defaultBoundaryBox(
        center: CLLocationCoordinate2D,
        acres: Double = 20
    ) -> [CLLocationCoordinate2D] {
        let sideM = sqrt(max(1, acres) * squareMetersPerAcre)
        let halfLatDeg = (sideM / 2) / metersPerDegreeLatitude
        let halfLngDeg = (sideM / 2) / metersPerDegreeLongitude(atLatitude: center.latitude)
        return [
            CLLocationCoordinate2D(latitude: center.latitude - halfLatDeg, longitude: center.longitude - halfLngDeg),
            CLLocationCoordinate2D(latitude: center.latitude - halfLatDeg, longitude: center.longitude + halfLngDeg),
            CLLocationCoordinate2D(latitude: center.latitude + halfLatDeg, longitude: center.longitude + halfLngDeg),
            CLLocationCoordinate2D(latitude: center.latitude + halfLatDeg, longitude: center.longitude - halfLngDeg),
        ]
    }

    // MARK: - Camera regions

    /// A map region framing a boundary polygon, with padding.
    static func region(forBoundary boundary: [CLLocationCoordinate2D], padding: Double = 1.4) -> MKCoordinateRegion? {
        guard !boundary.isEmpty else { return nil }
        return region(enclosing: boundary, padding: padding)
    }

    /// A map region framing all rectangles' corners (camera fallback when a profile has no region).
    static func region(forRectangles rectangles: [VineyardBlockRectangle], padding: Double = 1.4) -> MKCoordinateRegion? {
        let corners = rectangles.flatMap { $0.polygon }
        guard !corners.isEmpty else { return nil }
        return region(enclosing: corners, padding: padding)
    }

    private static func region(enclosing coords: [CLLocationCoordinate2D], padding: Double) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.001, (maxLat - minLat) * padding),
            longitudeDelta: max(0.001, (maxLng - minLng) * padding)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
