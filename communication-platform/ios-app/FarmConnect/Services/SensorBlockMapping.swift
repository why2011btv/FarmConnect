import Foundation

/// Maps live sensor devices from the API onto vineyard block ids (b1, b2, …).
enum SensorBlockMapping {
    static let maxAgeMs: Int64 = 24 * 60 * 60 * 1000

    /// Demo blocks wired to physical sensor nodes.
    static let assignedSensorBlockIds: Set<String> = ["b1", "b2"]

    private static let blockMatchers: [(blockId: String, patterns: [String])] = [
        ("b1", ["node 1", "node-1", "pi-node-1"]),
        ("b2", ["node 2", "node-2", "pi-node-2"]),
    ]

    static func blockId(for device: SensorDeviceOverview) -> String? {
        let name = device.name.lowercased()
        let id = device.id.lowercased()
        for (blockId, patterns) in blockMatchers {
            for pattern in patterns {
                if name.contains(pattern) || id.contains(pattern) {
                    return blockId
                }
            }
        }
        return nil
    }

    static func liveDataByBlockId(from devices: [SensorDeviceOverview]) -> [String: BlockLiveSensorData] {
        var result: [String: BlockLiveSensorData] = [:]
        for device in devices {
            guard let blockId = blockId(for: device),
                  let live = BlockLiveSensorData(device: device, maxAgeMs: maxAgeMs)
            else { continue }
            result[blockId] = live
        }
        return result
    }

    static func mergeLiveData(
        into blocks: [VineyardDemoBlock],
        devices: [SensorDeviceOverview]
    ) -> [VineyardDemoBlock] {
        let deviceByBlockId = devices.reduce(into: [String: SensorDeviceOverview]()) { result, device in
            guard let blockId = blockId(for: device) else { return }
            result[blockId] = device
        }

        return blocks.map { block in
            guard assignedSensorBlockIds.contains(block.id) else { return block }

            if let device = deviceByBlockId[block.id] {
                let connection = BlockSensorConnection(
                    deviceName: device.name,
                    isOnline: device.status.lowercased() == "online"
                )
                if let live = BlockLiveSensorData(device: device, maxAgeMs: maxAgeMs) {
                    return applyLive(block: block, live: live, connection: connection)
                }
                return block.withSensorConnection(connection)
            }

            let connection = BlockSensorConnection(
                deviceName: placeholderDeviceName(for: block.id),
                isOnline: false
            )
            return block.withSensorConnection(connection)
        }
    }

    private static func applyLive(
        block: VineyardDemoBlock,
        live: BlockLiveSensorData,
        connection: BlockSensorConnection
    ) -> VineyardDemoBlock {
        let readings = VineyardCanopyReading.fromLiveSensor(live)
        let analytics = VineyardCanopyAnalytics.summarize(readings: readings)
        let risk = VineyardDemoData.riskLevel(from: analytics)

        let draft = VineyardDemoBlock(
            id: block.id,
            name: block.name,
            locationLabel: block.locationLabel,
            polygon: block.polygon,
            center: block.center,
            riskLevel: risk,
            readings: readings,
            grapeVariety: block.grapeVariety,
            analytics: analytics,
            insights: [],
            liveSensor: live,
            sensorConnection: connection
        )
        let insights = VineyardCanopyAnalytics.insights(for: draft)
        return VineyardDemoBlock(
            id: draft.id,
            name: draft.name,
            locationLabel: draft.locationLabel,
            polygon: draft.polygon,
            center: draft.center,
            riskLevel: draft.riskLevel,
            readings: draft.readings,
            grapeVariety: draft.grapeVariety,
            analytics: draft.analytics,
            insights: insights,
            liveSensor: live,
            sensorConnection: connection
        )
    }

    private static func placeholderDeviceName(for blockId: String) -> String {
        switch blockId {
        case "b1": return "Node 1"
        case "b2": return "Node 2"
        default: return "Sensor node"
        }
    }
}

struct BlockSensorConnection: Equatable {
    let deviceName: String
    let isOnline: Bool
}

extension VineyardDemoBlock {
    func withSensorConnection(_ connection: BlockSensorConnection) -> VineyardDemoBlock {
        VineyardDemoBlock(
            id: id,
            name: name,
            locationLabel: locationLabel,
            polygon: polygon,
            center: center,
            riskLevel: riskLevel,
            readings: readings,
            grapeVariety: grapeVariety,
            analytics: analytics,
            insights: insights,
            liveSensor: liveSensor,
            sensorConnection: connection
        )
    }
}

struct BlockLiveSensorData: Equatable {
    let deviceId: String
    let deviceName: String
    let status: String
    let lastSeenAt: Date
    let temperatureC: Double?
    let humidityPct: Double?
    let soilMoisturePct: Double?

    init?(device: SensorDeviceOverview, maxAgeMs: Int64) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard device.lastSeenAt >= nowMs - maxAgeMs else { return nil }
        guard !device.readings.isEmpty else { return nil }

        let readingMap = Dictionary(uniqueKeysWithValues: device.readings.map { ($0.sensorType, $0) })
        let hasFreshReading = device.readings.contains { $0.createdAt >= nowMs - maxAgeMs }
        guard hasFreshReading else { return nil }

        deviceId = device.id
        deviceName = device.name
        status = device.status
        lastSeenAt = Date(timeIntervalSince1970: TimeInterval(device.lastSeenAt) / 1000)
        temperatureC = readingMap["temperature"]?.value
        humidityPct = readingMap["humidity"]?.value
        soilMoisturePct = readingMap["soil_moisture"]?.value
    }
}

extension VineyardCanopyReading {
    /// Builds canopy readings from the three live Pi sensors; neutral defaults fill gaps
    /// so mildew indices can still run on temp + humidity.
    static func fromLiveSensor(_ live: BlockLiveSensorData) -> VineyardCanopyReading {
        let tempF = live.temperatureC.map { $0 * 9 / 5 + 32 } ?? 70
        return VineyardCanopyReading(
            airTemperatureF: tempF,
            relativeHumidityPct: live.humidityPct ?? 50,
            leafWetnessHours: 0,
            soilMoisturePct: live.soilMoisturePct ?? 40,
            soilTemperatureF: tempF - 4,
            rainfallInches24h: 0,
            solarExposureMJ: 20,
            windSpeedMph: 8,
            windDirectionDegrees: 180
        )
    }
}
