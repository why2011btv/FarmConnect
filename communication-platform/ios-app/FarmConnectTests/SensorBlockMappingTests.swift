import XCTest
@testable import FarmConnect

final class SensorBlockMappingTests: XCTestCase {
    func testMapsNode0ToBlock1() {
        let device = SensorDeviceOverview(
            id: "lora-node-0",
            name: "Persephones Basket Node 0",
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

    func testMapsNode1ToBlock2() {
        let device = SensorDeviceOverview(
            id: "lora-node-1",
            name: "Persephones Basket Node 1",
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
        let staleMs = Int64(Date().timeIntervalSince1970 * 1000) - (8 * 24 * 60 * 60 * 1000)
        let device = SensorDeviceOverview(
            id: "lora-node-0",
            name: "Node 0",
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
        let merged = BlockReadingsComposer.compose(
            blocks: blocks,
            weatherByBlockId: [:],
            devices: [],
            includeSensorMapping: true
        )

        let block1 = merged.first { $0.id == "b1" }
        XCTAssertNotNil(block1?.sensorConnection)
        XCTAssertFalse(block1?.sensorConnection?.isOnline ?? true)
        XCTAssertNil(block1?.liveSensor)
    }

    func testOverlaysSensorFieldsOntoWeather() {
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
            id: "lora-node-0",
            name: "Persephones Basket Node 0",
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
            devices: [device],
            includeSensorMapping: true
        )

        let block1 = merged.first { $0.id == "b1" }
        XCTAssertEqual(block1?.readingSources.source(for: .airTemperature), .sensor)
        XCTAssertEqual(block1?.readingSources.source(for: .humidity), .sensor)
        XCTAssertEqual(block1?.readingSources.source(for: .soilMoisture), .sensor)
        XCTAssertEqual(block1?.readingSources.source(for: .windSpeed), .weather)
        XCTAssertEqual(block1?.readings.relativeHumidityPct, 80, accuracy: 0.01)
        XCTAssertEqual(block1?.readings.windSpeedMph, 5, accuracy: 0.01)
    }
}
