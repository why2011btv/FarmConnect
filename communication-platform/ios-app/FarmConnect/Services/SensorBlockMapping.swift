import Foundation

/// Maps live sensor devices onto vineyard blocks **by position**.
///
/// A node named "PB Node A3" drives the third block of whatever layout is showing. This is
/// deliberately positional rather than keyed on block id: the bundled sample layout numbers its
/// blocks `b1…b8`, while a layout generated for a real customer numbers them `gen-1…gen-N`. Keying
/// on the id meant sensor data only ever appeared on the sample vineyard, which is exactly the
/// wrong way round for a shipping product.
enum SensorBlockMapping {
    static let maxAgeMs: Int64 = 7 * 24 * 60 * 60 * 1000

    /// Upper bound on the node suffix we will parse. Previously capped at 8 to match the sample
    /// layout's block count, which silently dropped A9 and beyond.
    static let maxNodeIndex = 64

    /// Legacy fallbacks when no PB Node A# device is present.
    private static let legacyMatchers: [(index: Int, patterns: [String])] = [
        (1, ["node 0", "node-0", "lora-node-0"]),
        (2, ["node 1", "node-1", "lora-node-1"]),
    ]

    /// 1-based position of the block this device belongs to, or nil if the name carries no index.
    static func nodeIndex(for device: SensorDeviceOverview) -> Int? {
        let candidates = [device.id, device.name].map { $0.lowercased() }

        // Prefer PB Node A1 / pb-node-A1 -> 1, A2 -> 2, ...
        for text in candidates {
            if let number = extractSeriesANumber(from: text) {
                return number
            }
        }

        for (index, patterns) in legacyMatchers {
            for pattern in patterns {
                if candidates.contains(where: { $0.contains(pattern) }) {
                    return index
                }
            }
        }
        return nil
    }

    /// Parses `A1`, `a2`, `pb-node-A3`, `PB Node A4`, etc. into 1…`maxNodeIndex`.
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
                  (1...maxNodeIndex).contains(number)
            else { continue }
            return number
        }
        return nil
    }

    /// Name shown for a block whose node is provisioned but has never reported.
    static func placeholderDeviceName(forIndex index: Int) -> String {
        "PB Node A\(index)"
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
