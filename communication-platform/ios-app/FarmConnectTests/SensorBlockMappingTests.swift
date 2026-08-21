import XCTest
@testable import FarmConnect

final class SensorBlockMappingTests: XCTestCase {
    func testMapsA1ToPosition1() {
        let device = SensorDeviceOverview(
            id: "pb-node-A1",
            name: "PB Node A1",
            farmName: "Persephone Farm",
            locationLabel: "Block 1",
            status: "online",
            lastSeenAt: Int64(Date().timeIntervalSince1970 * 1000),
            readings: [
                SensorReading(sensorType: "temperature", value: 22.5, unit: "C", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
            ]
        )

        XCTAssertEqual(SensorBlockMapping.nodeIndex(for: device), 1)
    }

    func testMapsA2ToPosition2() {
        let device = SensorDeviceOverview(
            id: "pb-node-A2",
            name: "PB Node A2",
            farmName: "Persephone Farm",
            locationLabel: "Block 2",
            status: "online",
            lastSeenAt: Int64(Date().timeIntervalSince1970 * 1000),
            readings: [
                SensorReading(sensorType: "temperature", value: 20.0, unit: "C", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
            ]
        )

        XCTAssertEqual(SensorBlockMapping.nodeIndex(for: device), 2)
    }

    func testMapsA8ToPosition8() {
        let device = SensorDeviceOverview(
            id: "pb-node-A8",
            name: "PB Node A8",
            farmName: "Persephone Farm",
            locationLabel: "Block 8",
            status: "online",
            lastSeenAt: Int64(Date().timeIntervalSince1970 * 1000),
            readings: [
                SensorReading(sensorType: "humidity", value: 55.0, unit: "%", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
            ]
        )

        XCTAssertEqual(SensorBlockMapping.nodeIndex(for: device), 8)
    }

    func testLegacyNode0StillMapsToPosition1() {
        let device = SensorDeviceOverview(
            id: "lora-node-0",
            name: "Persephones Basket Node 0",
            farmName: "Persephone Farm",
            locationLabel: "North Plot",
            status: "online",
            lastSeenAt: Int64(Date().timeIntervalSince1970 * 1000),
            readings: [
                SensorReading(sensorType: "temperature", value: 22.5, unit: "C", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
            ]
        )

        XCTAssertEqual(SensorBlockMapping.nodeIndex(for: device), 1)
    }

    func testRejectsStaleDevice() {
        let staleMs = Int64(Date().timeIntervalSince1970 * 1000) - (8 * 24 * 60 * 60 * 1000)
        let device = SensorDeviceOverview(
            id: "pb-node-A1",
            name: "PB Node A1",
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

    /// A farm with no nodes at all must not invent offline hardware. Previously every block in
    /// b1...b8 showed an "offline" node whether or not one had ever been provisioned.
    func testShowsNoSensorRowWhenFarmHasNoNodes() {
        let rectangles = VineyardDemoData.defaultRectangles
        let blocks = VineyardDemoData.makeBlocks(rectangles: rectangles, settings: [:])
        let merged = BlockReadingsComposer.compose(
            blocks: blocks,
            weatherByBlockId: [:],
            devices: []
        )

        XCTAssertTrue(merged.allSatisfy { $0.sensorConnection == nil })
        XCTAssertTrue(merged.allSatisfy { $0.liveSensor == nil })
    }

    /// A gap in the series is real information: A1 and A3 reported, so A2 exists and is silent.
    func testMarksGapInNodeSeriesOffline() {
        let rectangles = VineyardDemoData.defaultRectangles
        let blocks = VineyardDemoData.makeBlocks(rectangles: rectangles, settings: [:])
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        func node(_ n: Int) -> SensorDeviceOverview {
            SensorDeviceOverview(
                id: "pb-node-A\(n)", name: "PB Node A\(n)", farmName: "Farm",
                locationLabel: "Block \(n)", status: "online", lastSeenAt: now,
                readings: [SensorReading(sensorType: "temperature", value: 20, unit: "C", createdAt: now)]
            )
        }

        let merged = BlockReadingsComposer.compose(
            blocks: blocks, weatherByBlockId: [:], devices: [node(1), node(3)]
        )

        XCTAssertEqual(merged[0].sensorConnection?.isOnline, true)   // A1 reported
        XCTAssertEqual(merged[1].sensorConnection?.isOnline, false)  // A2 missing -> offline
        XCTAssertEqual(merged[2].sensorConnection?.isOnline, true)   // A3 reported
        XCTAssertNil(merged[3].sensorConnection)                     // past the fleet -> nothing
    }

    /// Sensors must attach to a generated customer layout ("gen-N" ids), not just the sample
    /// layout ("bN" ids). Keying on block id was why a customer's own vineyard showed no sensors.
    func testMapsOntoGeneratedLayoutBlockIds() {
        let rects = (1...3).map { i in
            VineyardBlockRectangle(
                id: "gen-\(i)", centerLatitude: 38.0 + Double(i) / 1000, centerLongitude: -122.0,
                halfLatitudeSpan: 0.0003, halfLongitudeSpan: 0.0003
            )
        }
        let blocks = VineyardDemoData.makeBlocks(rectangles: rects, settings: [:])
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let device = SensorDeviceOverview(
            id: "farm_abc-A2", name: "PB Node A2", farmName: "Smith Vineyard",
            locationLabel: "Block 2", status: "online", lastSeenAt: now,
            readings: [SensorReading(sensorType: "temperature", value: 21, unit: "C", createdAt: now)]
        )

        let merged = BlockReadingsComposer.compose(
            blocks: blocks, weatherByBlockId: [:], devices: [device]
        )

        XCTAssertEqual(merged[1].id, "gen-2")
        XCTAssertEqual(merged[1].sensorConnection?.deviceName, "PB Node A2")
        XCTAssertEqual(merged[1].liveSensor?.deviceId, "farm_abc-A2")
    }

    /// A9/A10 were silently dropped by a 1...8 cap that matched the sample layout's block count.
    func testParsesNodeIndexesBeyondEight() {
        XCTAssertEqual(SensorBlockMapping.extractSeriesANumber(from: "pb-node-a10"), 10)
        XCTAssertEqual(SensorBlockMapping.extractSeriesANumber(from: "pb node a12"), 12)
    }

    func testOverlaysSensorFieldsOntoWeatherFromA1() throws {
        let rectangles = VineyardDemoData.defaultRectangles
        let blocks = VineyardDemoData.makeBlocks(rectangles: rectangles, settings: [:])
        let weather = VineyardCanopyReading(
            airTemperatureF: 70,
            relativeHumidityPct: 50,
            leafWetnessHours: 1,
            soilMoisturePct: 30,
            soilTemperatureF: 65,
            rainfallInches24h: 0.1,
            solarExposureMJ: 18,
            windSpeedMph: 5,
            windDirectionDegrees: 90
        )
        let device = SensorDeviceOverview(
            id: "pb-node-A1",
            name: "PB Node A1",
            farmName: "Farm",
            locationLabel: "Plot",
            status: "online",
            lastSeenAt: Int64(Date().timeIntervalSince1970 * 1000),
            readings: [
                SensorReading(sensorType: "temperature", value: 20.0, unit: "C", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
                SensorReading(sensorType: "humidity", value: 80.0, unit: "%", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
                SensorReading(sensorType: "soil_moisture", value: 44.0, unit: "%", createdAt: Int64(Date().timeIntervalSince1970 * 1000)),
            ]
        )

        let merged = BlockReadingsComposer.compose(
            blocks: blocks,
            weatherByBlockId: ["b1": weather],
            devices: [device]
        )

        // XCTAssertEqual(_:_:accuracy:) takes non-optionals, so unwrap first. This is why the
        // suite had stopped compiling.
        let block1 = try XCTUnwrap(merged.first { $0.id == "b1" })
        XCTAssertEqual(block1.readingSources.source(for: .airTemperature), .sensor)
        XCTAssertEqual(block1.readingSources.source(for: .humidity), .sensor)
        XCTAssertEqual(block1.readingSources.source(for: .soilMoisture), .sensor)
        XCTAssertEqual(block1.readingSources.source(for: .windSpeed), .weather)
        XCTAssertEqual(block1.readings.relativeHumidityPct, 80, accuracy: 0.01)
        XCTAssertEqual(block1.readings.windSpeedMph, 5, accuracy: 0.01)
    }
}
