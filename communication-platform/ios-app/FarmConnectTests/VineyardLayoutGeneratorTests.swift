import CoreLocation
import XCTest
@testable import FarmConnect

final class VineyardLayoutGeneratorTests: XCTestCase {

    // A ~1 km square near Running Brook (Dartmouth, MA). 1 km^2 ≈ 247.1 acres.
    private func kilometerSquare(center: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let halfLat = 500.0 / VineyardLayoutGenerator.metersPerDegreeLatitude
        let halfLng = 500.0 / VineyardLayoutGenerator.metersPerDegreeLongitude(atLatitude: center.latitude)
        return [
            .init(latitude: center.latitude - halfLat, longitude: center.longitude - halfLng),
            .init(latitude: center.latitude - halfLat, longitude: center.longitude + halfLng),
            .init(latitude: center.latitude + halfLat, longitude: center.longitude + halfLng),
            .init(latitude: center.latitude + halfLat, longitude: center.longitude - halfLng),
        ]
    }

    func testGeodesicAreaOfKilometerSquare() {
        let center = CLLocationCoordinate2D(latitude: 41.68245, longitude: -71.00075)
        let acres = VineyardLayoutGenerator.geodesicAreaAcres(kilometerSquare(center: center))
        // 1 km^2 = 247.105 acres; allow projection slack.
        XCTAssertEqual(acres, 247.1, accuracy: 5.0)
    }

    func testAreaDegenerateInputs() {
        XCTAssertEqual(VineyardLayoutGenerator.geodesicAreaAcres([]), 0)
        XCTAssertEqual(
            VineyardLayoutGenerator.geodesicAreaAcres([
                .init(latitude: 41, longitude: -71),
                .init(latitude: 41, longitude: -71),
            ]),
            0
        )
    }

    func testRecommendedBlockCount() {
        XCTAssertEqual(VineyardLayoutGenerator.recommendedBlockCount(acres: 25, acresPerBlock: 10), 3)
        XCTAssertEqual(VineyardLayoutGenerator.recommendedBlockCount(acres: 10, acresPerBlock: 10), 2) // min floor
        XCTAssertEqual(VineyardLayoutGenerator.recommendedBlockCount(acres: 5, acresPerBlock: 10), 2)  // min floor
        XCTAssertEqual(VineyardLayoutGenerator.recommendedBlockCount(acres: 100, acresPerBlock: 10), 10)
        XCTAssertEqual(VineyardLayoutGenerator.recommendedBlockCount(acres: 0, acresPerBlock: 10), 2)
    }

    func testGenerateBlocksAllInsideBoundary() {
        let center = CLLocationCoordinate2D(latitude: 41.68245, longitude: -71.00075)
        let boundary = kilometerSquare(center: center)
        let rects = VineyardLayoutGenerator.generateBlocks(boundary: boundary, count: 12)

        XCTAssertFalse(rects.isEmpty)
        // Every kept block's center must be inside the boundary (convex square => all grid cells inside).
        for rect in rects {
            XCTAssertTrue(GeoPolygon.contains(rect.center, polygon: boundary), "block \(rect.id) outside boundary")
        }
        // Ids are contiguous gen-1..gen-n.
        XCTAssertEqual(rects.map(\.id), (1...rects.count).map { "gen-\($0)" })
    }

    func testGenerateBlocksClipsConcaveBoundary() {
        // L-shaped boundary: a cell in the missing quadrant should be dropped.
        let lat0 = 41.0, lng0 = -71.0
        let d = 0.01
        let lShape: [CLLocationCoordinate2D] = [
            .init(latitude: lat0, longitude: lng0),
            .init(latitude: lat0, longitude: lng0 + 2 * d),
            .init(latitude: lat0 + d, longitude: lng0 + 2 * d),
            .init(latitude: lat0 + d, longitude: lng0 + d),
            .init(latitude: lat0 + 2 * d, longitude: lng0 + d),
            .init(latitude: lat0 + 2 * d, longitude: lng0),
        ]
        let rects = VineyardLayoutGenerator.generateBlocks(boundary: lShape, count: 16)
        XCTAssertFalse(rects.isEmpty)
        for rect in rects {
            XCTAssertTrue(GeoPolygon.contains(rect.center, polygon: lShape))
        }
    }

    func testGenerateBlocksRespectsRotation() {
        let boundary = kilometerSquare(center: .init(latitude: 41.68, longitude: -71.0))
        let rects = VineyardLayoutGenerator.generateBlocks(boundary: boundary, count: 4, rotationDegrees: 7)
        XCTAssertTrue(rects.allSatisfy { $0.rotationDegrees == 7 })
    }

    func testDefaultBoundaryBoxAcreage() {
        let center = CLLocationCoordinate2D(latitude: 41.68, longitude: -71.0)
        let box = VineyardLayoutGenerator.defaultBoundaryBox(center: center, acres: 20)
        let acres = VineyardLayoutGenerator.geodesicAreaAcres(box)
        XCTAssertEqual(acres, 20, accuracy: 1.0)
    }
}
