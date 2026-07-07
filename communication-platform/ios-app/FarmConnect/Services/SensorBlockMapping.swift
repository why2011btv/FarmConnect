import Foundation

/// Maps live sensor devices from the API onto vineyard block ids (b1, b2, …).
enum SensorBlockMapping {
    static let maxAgeMs: Int64 = 7 * 24 * 60 * 60 * 1000

    /// Demo blocks wired to physical sensor nodes.
    static let assignedSensorBlockIds: Set<String> = ["b1", "b2"]

    private static let blockMatchers: [(blockId: String, patterns: [String])] = [
        ("b1", ["node 0", "node-0", "lora-node-0"]),
        ("b2", ["node 1", "node-1", "lora-node-1", "pi-node-1"]),
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

    static func placeholderDeviceName(for blockId: String) -> String {
        switch blockId {
        case "b1": return "Node 0"
        case "b2": return "Node 1"
        default: return "Sensor node"
        }
    }
}

struct BlockSensorConnection: Equatable {
    let deviceName: String
    let isOnline: Bool
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
