import CoreLocation
import Foundation

enum ReadingDataSource: String, Equatable {
    case sensor
    case weather
}

enum CanopyMetricField: String, CaseIterable, Hashable {
    case airTemperature
    case humidity
    case leafWetness
    case soilMoisture
    case soilTemperature
    case rainfall
    case solar
    case windSpeed
    case windDirection
}

struct CanopyReadingSources: Equatable {
    var values: [CanopyMetricField: ReadingDataSource]

    init(all source: ReadingDataSource) {
        values = Dictionary(uniqueKeysWithValues: CanopyMetricField.allCases.map { ($0, source) })
    }

    func source(for field: CanopyMetricField) -> ReadingDataSource {
        values[field] ?? .weather
    }

    mutating func set(_ field: CanopyMetricField, to source: ReadingDataSource) {
        values[field] = source
    }
}

enum BlockReadingsComposer {
    /// Merges weather and live sensor readings into each block.
    ///
    /// Devices attach to blocks by position (node A3 -> third block), so this works identically on
    /// the bundled sample layout and on a layout generated for a customer's own vineyard.
    static func compose(
        blocks: [VineyardDemoBlock],
        weatherByBlockId: [String: VineyardCanopyReading],
        devices: [SensorDeviceOverview]
    ) -> [VineyardDemoBlock] {
        // Resolve one device per position up front, preferring a PB Node A# over a legacy
        // lora/pi node when both claim the same slot.
        var deviceByIndex: [Int: SensorDeviceOverview] = [:]
        for device in devices {
            guard let index = SensorBlockMapping.nodeIndex(for: device) else { continue }
            if let existing = deviceByIndex[index],
               SensorBlockMapping.extractSeriesANumber(from: existing.id.lowercased()) != nil
                || SensorBlockMapping.extractSeriesANumber(from: existing.name.lowercased()) != nil {
                continue
            }
            deviceByIndex[index] = device
        }

        // Blocks past the highest node we know about were never instrumented, so they get no
        // sensor row at all rather than a misleading "offline" placeholder.
        let instrumentedCount = deviceByIndex.keys.max() ?? 0

        return blocks.enumerated().map { offset, block in
            let position = offset + 1
            let baseReading = weatherByBlockId[block.id] ?? block.readings
            var sources = weatherByBlockId[block.id] != nil
                ? CanopyReadingSources(all: .weather)
                : CanopyReadingSources(all: .weather)

            var reading = baseReading
            var liveSensor: BlockLiveSensorData?
            var sensorConnection: BlockSensorConnection?

            if let device = deviceByIndex[position] {
                sensorConnection = BlockSensorConnection(
                    deviceName: device.name,
                    isOnline: device.status.lowercased() == "online"
                )
                if let live = BlockLiveSensorData(device: device, maxAgeMs: SensorBlockMapping.maxAgeMs) {
                    liveSensor = live
                    reading = mergeSensor(live, into: reading)
                    if live.temperatureC != nil { sources.set(.airTemperature, to: .sensor) }
                    if live.humidityPct != nil { sources.set(.humidity, to: .sensor) }
                    if live.soilMoisturePct != nil { sources.set(.soilMoisture, to: .sensor) }
                }
            } else if position <= instrumentedCount {
                // A gap in the series: this block's node exists in the fleet but has not reported.
                sensorConnection = BlockSensorConnection(
                    deviceName: SensorBlockMapping.placeholderDeviceName(forIndex: position),
                    isOnline: false
                )
            }

            return rebuildBlock(
                block,
                readings: reading,
                sources: sources,
                liveSensor: liveSensor,
                sensorConnection: sensorConnection
            )
        }
    }

    private static func mergeSensor(_ live: BlockLiveSensorData, into base: VineyardCanopyReading) -> VineyardCanopyReading {
        let tempF = live.temperatureC.map { $0 * 9 / 5 + 32 } ?? base.airTemperatureF
        return VineyardCanopyReading(
            airTemperatureF: tempF,
            relativeHumidityPct: live.humidityPct ?? base.relativeHumidityPct,
            leafWetnessHours: base.leafWetnessHours,
            soilMoisturePct: live.soilMoisturePct ?? base.soilMoisturePct,
            soilTemperatureF: base.soilTemperatureF,
            rainfallInches24h: base.rainfallInches24h,
            solarExposureMJ: base.solarExposureMJ,
            windSpeedMph: base.windSpeedMph,
            windDirectionDegrees: base.windDirectionDegrees
        )
    }

    private static func rebuildBlock(
        _ block: VineyardDemoBlock,
        readings: VineyardCanopyReading,
        sources: CanopyReadingSources,
        liveSensor: BlockLiveSensorData?,
        sensorConnection: BlockSensorConnection?
    ) -> VineyardDemoBlock {
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
            liveSensor: liveSensor,
            sensorConnection: sensorConnection,
            readingSources: sources
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
            liveSensor: liveSensor,
            sensorConnection: sensorConnection,
            readingSources: sources
        )
    }
}
