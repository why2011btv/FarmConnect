import XCTest
@testable import FarmConnect

final class SensorBlockMappingTests: XCTestCase {
    func testMapsNode1ToBlock1ByName() {
        let device = SensorDeviceOverview(
            id: "persephone-node-1",
            name: "Persephones Basket Node 1",
            farmName: "Persephone Farm",
            locationLabel: "North Plot",
            status: "online",
            lastSeenAt: Int64(Date().timeIntervalSince1970 * 1000),
            readings: [
                SensorReading(sensorType: "temperature", value: 22.5, unit: "C", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
                SensorReading(sensorType: "humidity", value: 61.0, unit: "%", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
                SensorReading(sensorType: "soil_moisture", value: 38.0, unit: "%", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
            ]
        )

        XCTAssertEqual(SensorBlockMapping.blockId(for: device), "b1")
    }

    func testMapsNode2ToBlock2ById() {
        let device = SensorDeviceOverview(
            id: "pi-node-2",
            name: "Raspberry Pi Node 2",
            farmName: "Persephone Farm",
            locationLabel: "South Plot",
            status: "online",
            lastSeenAt: Int64(Date().timeIntervalSince1970 * 1000),
            readings: [
                SensorReading(sensorType: "temperature", value: 20.0, unit: "C", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
            ]
        )

        XCTAssertEqual(SensorBlockMapping.blockId(for: device), "b2")
    }

    func testRejectsStaleDevice() {
        let staleMs = Int64(Date().timeIntervalSince1970 * 1000) - (25 * 60 * 60 * 1000)
        let device = SensorDeviceOverview(
            id: "pi-node-1",
            name: "Node 1",
            farmName: "Farm",
            locationLabel: "Plot",
            status: "online",
            lastSeenAt: staleMs,
            readings: [
                SensorReading(sensorType: "temperature", value: 20.0, unit: "C", createdAt: staleMs),
            ]
        )

        XCTAssertNil(BlockLiveSensorData(device: device, maxAgeMs: SensorBlockMapping.maxAgeMs))
    }

    func testMarksAssignedBlockOfflineWhenDeviceMissing() {
        let rectangles = VineyardDemoData.defaultRectangles
        let blocks = VineyardDemoData.makeBlocks(rectangles: rectangles, settings: [:])
        let merged = SensorBlockMapping.mergeLiveData(into: blocks, devices: [])

        let block1 = merged.first { $0.id == "b1" }
        XCTAssertNotNil(block1?.sensorConnection)
        XCTAssertFalse(block1?.sensorConnection?.isOnline ?? true)
        XCTAssertNil(block1?.liveSensor)
    }
}
