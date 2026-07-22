import Foundation

/// Maps live sensor devices from the API onto vineyard block ids (b1, b2, …).
enum SensorBlockMapping {
    static let maxAgeMs: Int64 = 7 * 24 * 60 * 60 * 1000

    /// Demo blocks that can show a sensor online/offline indicator (Running Brook has 8 blocks).
    static let assignedSensorBlockIds: Set<String> = [
        "b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8",
    ]

    /// Legacy fallbacks when no PB Node A# device is present.
    private static let legacyMatchers: [(blockId: String, patterns: [String])] = [
        ("b1", ["node 0", "node-0", "lora-node-0"]),
        ("b2", ["node 1", "node-1", "lora-node-1"]),
    ]

    static func blockId(for device: SensorDeviceOverview) -> String? {
        let candidates = [device.id, device.name].map { $0.lowercased() }

        // Prefer PB Node A1 / pb-node-A1 → b1, A2 → b2, …
        for text in candidates {
            if let number = extractSeriesANumber(from: text) {
                return "b\(number)"
            }
        }

        for (blockId, patterns) in legacyMatchers {
            for pattern in patterns {
                if candidates.contains(where: { $0.contains(pattern) }) {
                    return blockId
                }
            }
        }
        return nil
    }

    /// Parses `A1`, `a2`, `pb-node-A3`, `PB Node A4`, etc. into 1…8.
    static func extractSeriesANumber(from text: String) -> Int? {
        let patterns = [
            #"pb[-_]?node[-_]?a(\d+)"#,
            #"\bnode\s*a(\d+)\b"#,
            #"\ba(\d+)\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let numberRange = Range(match.range(at: 1), in: text),
                  let number = Int(text[numberRange]),
                  (1...8).contains(number)
            else { continue }
            return number
        }
        return nil
    }

    static func placeholderDeviceName(for blockId: String) -> String {
        if blockId.hasPrefix("b"), let n = Int(blockId.dropFirst()), (1...8).contains(n) {
            return "PB Node A\(n)"
        }
        return "Sensor node"
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
