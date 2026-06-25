import XCTest
@testable import FarmConnect

@MainActor
final class VineyardBlockLayoutStoreTests: XCTestCase {

    private let keys = [
        "vineyard.slot.demo.v2",
        "vineyard.slot.planning.v2",
        "vineyard.layout.mode.v2",
        "vineyard.demo.block.rectangles.v1",
        "vineyard.demo.block.settings.v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private func sampleRects(prefix: String, n: Int) -> [VineyardBlockRectangle] {
        (1...n).map { i in
            VineyardBlockRectangle(
                id: "\(prefix)-\(i)",
                centerLatitude: 41.0 + Double(i) * 0.001,
                centerLongitude: -71.0,
                halfLatitudeSpan: 0.0003,
                halfLongitudeSpan: 0.0004,
                rotationDegrees: 0
            )
        }
    }

    func testFreshInstallShowsRunningBrookDemo() {
        let store = VineyardBlockLayoutStore()
        XCTAssertEqual(store.mode, .demo)
        // Bundled demo = 8 hand-tuned blocks b1..b8.
        XCTAssertEqual(store.rectangles.count, VineyardDemoData.defaultRectangles.count)
        XCTAssertEqual(Set(store.rectangles.map(\.id)), Set(VineyardDemoData.defaultRectangles.map(\.id)))
    }

    func testInstallPlanningDoesNotTouchDemoSlot() {
        let store = VineyardBlockLayoutStore()
        let demoBefore = store.slots.demo

        let profile = VineyardProfile(
            name: "Test Vineyard",
            centerLatitude: 41.68, centerLongitude: -71.0,
            latitudeDelta: 0.006, longitudeDelta: 0.004,
            boundary: nil, acreage: 25, source: "osm"
        )
        store.installPlanningLayout(rectangles: sampleRects(prefix: "gen", n: 3), profile: profile)

        // installPlanningLayout switches to planning mode.
        XCTAssertEqual(store.mode, .planning)
        XCTAssertEqual(store.rectangles.count, 3)
        XCTAssertEqual(store.activeProfile?.name, "Test Vineyard")
        // Demo slot is byte-identical.
        XCTAssertEqual(store.slots.demo, demoBefore)
    }

    func testEditingPlanningDoesNotMutateDemo() {
        let store = VineyardBlockLayoutStore()
        let demoBefore = store.slots.demo
        let profile = VineyardProfile(
            name: "V", centerLatitude: 41, centerLongitude: -71,
            latitudeDelta: 0.006, longitudeDelta: 0.004, boundary: nil, acreage: 25, source: "osm"
        )
        store.installPlanningLayout(rectangles: sampleRects(prefix: "gen", n: 2), profile: profile)
        store.updateRectangle(id: "gen-1") { $0.centerLatitude += 0.01 }

        XCTAssertEqual(store.slots.demo, demoBefore)
        XCTAssertNotEqual(store.slots.planning.rectangles.first?.centerLatitude, 41.001)
    }

    func testSwitchModeIsReversibleAndIsolated() {
        let store = VineyardBlockLayoutStore()
        let profile = VineyardProfile(
            name: "V", centerLatitude: 41, centerLongitude: -71,
            latitudeDelta: 0.006, longitudeDelta: 0.004, boundary: nil, acreage: 25, source: "osm"
        )
        store.installPlanningLayout(rectangles: sampleRects(prefix: "gen", n: 4), profile: profile)
        XCTAssertEqual(store.rectangles.count, 4) // planning

        store.setMode(.demo)
        XCTAssertEqual(store.rectangles.count, VineyardDemoData.defaultRectangles.count)

        store.setMode(.planning)
        XCTAssertEqual(store.rectangles.count, 4)
    }

    func testPromotePlanningToDemoIsDeepCopy() {
        let store = VineyardBlockLayoutStore()
        let profile = VineyardProfile(
            name: "Promoted", centerLatitude: 41, centerLongitude: -71,
            latitudeDelta: 0.006, longitudeDelta: 0.004, boundary: nil, acreage: 25, source: "osm"
        )
        store.installPlanningLayout(rectangles: sampleRects(prefix: "gen", n: 3), profile: profile)
        store.promoteActiveLayoutToDemo()

        store.setMode(.demo)
        XCTAssertEqual(store.rectangles.count, 3)
        XCTAssertEqual(store.activeProfile?.name, "Promoted")

        // Editing demo after promotion must not change planning (independent value copies).
        let planningBefore = store.slots.planning
        store.updateRectangle(id: "gen-1") { $0.rotationDegrees = 30 }
        XCTAssertEqual(store.slots.planning, planningBefore)
    }

    func testMakeBlocksSynthesizesForGeneratedIds() {
        // gen-* ids are not in blockTemplates; makeBlocks must still produce blocks for them.
        let rects = sampleRects(prefix: "gen", n: 5)
        let blocks = VineyardDemoData.makeBlocks(rectangles: rects, settings: [:])
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(Set(blocks.map(\.id)), Set(rects.map(\.id)))
    }

    func testV1MigrationPreservesHandTunedLayout() {
        // Seed legacy v1 keys, then a fresh store should adopt them into the demo slot.
        let legacy = sampleRects(prefix: "b", n: 8) // ids b-1.. won't match defaults, but count/exist
        let data = try! JSONEncoder().encode(legacy)
        UserDefaults.standard.set(data, forKey: "vineyard.demo.block.rectangles.v1")

        let store = VineyardBlockLayoutStore()
        XCTAssertEqual(store.mode, .demo)
        XCTAssertEqual(store.rectangles.count, 8)
        XCTAssertEqual(Set(store.rectangles.map(\.id)), Set(legacy.map(\.id)))
    }
}
