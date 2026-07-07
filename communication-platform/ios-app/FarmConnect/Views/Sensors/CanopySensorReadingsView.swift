import SwiftUI

enum CanopyReadingsLayout {
    case regular
    case compact
}

struct CanopySensorReadingsView: View {
    let block: VineyardDemoBlock?
    var allBlocks: [VineyardDemoBlock] = []
    var layout: CanopyReadingsLayout = .regular
    var isLoadingWeather = false

    var body: some View {
        Group {
            if let block {
                blockReadings(block)
            } else {
                vineyardOverview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: layout == .compact ? nil : .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var gridColumns: [GridItem] {
        let count = layout == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    @ViewBuilder
    private func blockReadings(_ block: VineyardDemoBlock) -> some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            blockHeader(for: block)
            sourceLegend(for: block)
            if isLoadingWeather {
                ProgressView("Loading local weather…")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                metricsGrid(for: block)
            }
        }
        .padding(.horizontal, layout == .compact ? 12 : 14)
        .padding(.vertical, 12)

        if layout == .compact {
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func metricsGrid(for block: VineyardDemoBlock) -> some View {
        let r = block.readings
        let s = block.readingSources
        return LazyVGrid(columns: gridColumns, spacing: 8) {
            metricCard(
                "Air temp",
                value: airTemperatureLabel(block: block, reading: r),
                icon: "thermometer.medium",
                tint: .orange,
                source: s.source(for: .airTemperature)
            )
            metricCard(
                "Humidity",
                value: format(r.relativeHumidityPct, unit: "%"),
                icon: "humidity.fill",
                tint: .blue,
                source: s.source(for: .humidity)
            )
            metricCard(
                "Leaf wet",
                value: format(r.leafWetnessHours, unit: "h"),
                icon: "drop.fill",
                tint: .teal,
                source: s.source(for: .leafWetness)
            )
            metricCard(
                "Soil moist",
                value: format(r.soilMoisturePct, unit: "%"),
                icon: "drop.circle.fill",
                tint: .brown,
                source: s.source(for: .soilMoisture)
            )
            metricCard(
                "Soil temp",
                value: format(r.soilTemperatureF, unit: "°F"),
                icon: "thermometer.sun.fill",
                tint: .orange,
                source: s.source(for: .soilTemperature)
            )
            metricCard(
                "Rain 24h",
                value: format(r.rainfallInches24h, unit: "in"),
                icon: "cloud.rain.fill",
                tint: .indigo,
                source: s.source(for: .rainfall)
            )
            metricCard(
                "Solar",
                value: format(r.solarExposureMJ, unit: "MJ/m²"),
                icon: "sun.max.fill",
                tint: .yellow,
                source: s.source(for: .solar)
            )
            metricCard(
                "Wind",
                value: format(r.windSpeedMph, unit: "mph"),
                icon: "wind",
                tint: .cyan,
                source: s.source(for: .windSpeed)
            )
            metricCard(
                "Wind dir",
                value: "\(r.windDirectionLabel) \(Int(r.windDirectionDegrees))°",
                icon: "location.north.fill",
                tint: .mint,
                source: s.source(for: .windDirection)
            )
        }
    }

    private func airTemperatureLabel(block: VineyardDemoBlock, reading: VineyardCanopyReading) -> String {
        if block.readingSources.source(for: .airTemperature) == .sensor,
           let tempC = block.liveSensor?.temperatureC {
            return String(format: "%.1f °C (%.1f °F)", tempC, tempC * 9 / 5 + 32)
        }
        return format(reading.airTemperatureF, unit: "°F")
    }

    @ViewBuilder
    private var vineyardOverview: some View {
        let summaryBlocks = allBlocks.isEmpty ? [] : allBlocks
        let highRisk = summaryBlocks.filter { $0.riskLevel == .high }.count
        let liveCount = summaryBlocks.filter { $0.liveSensor != nil }.count
        let sensorBlocks = summaryBlocks.filter { $0.sensorConnection != nil }.count

        let content = VStack(alignment: .leading, spacing: layout == .compact ? 10 : 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Vineyard overview")
                    .font(layout == .compact ? .subheadline.weight(.semibold) : .headline)
                Text("Tap a block on the map for readings and recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                overviewTile(
                    title: "Live nodes",
                    value: "\(liveCount)",
                    caption: liveCount > 0 ? "Sensor data active" : "Weather-backed blocks",
                    icon: "sensor.tag.radiowaves.forward.fill",
                    tint: liveCount > 0 ? .green : .blue
                )
                overviewTile(
                    title: "High-risk blocks",
                    value: "\(highRisk)",
                    caption: sensorBlocks > 0 ? "\(sensorBlocks) sensor blocks" : "Fungus pressure",
                    icon: "leaf.fill",
                    tint: .red
                )
            }

            sourceLegendRow
            riskSummaryRow
        }
        .padding(layout == .compact ? 12 : 16)

        if layout == .compact {
            content
        } else {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var sourceLegendRow: some View {
        HStack(spacing: 12) {
            legendChip(color: .green.opacity(0.35), label: "Field sensor")
            legendChip(color: .blue.opacity(0.28), label: "Local weather")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func sourceLegend(for block: VineyardDemoBlock) -> some View {
        let hasSensor = block.readingSources.values.values.contains(.sensor)
        let hasWeather = block.readingSources.values.values.contains(.weather)
        return Group {
            if hasSensor && hasWeather {
                sourceLegendRow
            }
        }
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
        }
    }

    private var riskSummaryRow: some View {
        let low = allBlocks.filter { $0.riskLevel == .low }.count
        let moderate = allBlocks.filter { $0.riskLevel == .moderate }.count
        let high = allBlocks.filter { $0.riskLevel == .high }.count

        return VStack(alignment: .leading, spacing: 6) {
            Text("Crop health summary")
                .font(.caption.weight(.semibold))
            HStack(spacing: 12) {
                riskChip(count: low, label: "Low", color: .green)
                riskChip(count: moderate, label: "Mod", color: .orange)
                riskChip(count: high, label: "High", color: .red)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func riskChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(layout == .compact ? .headline.bold() : .title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func blockHeader(for block: VineyardDemoBlock) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.name)
                    .font(.subheadline.weight(.semibold))
                locationLabelRow(block: block)
                if let live = block.liveSensor {
                    Text("Sensor updated \(live.lastSeenAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let connection = block.sensorConnection {
                    Text(connection.deviceName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if block.grapeVariety != .notSpecified {
                    Text(block.grapeVariety.displayName)
                        .font(.caption.weight(.medium))
                }
            }
            Spacer(minLength: 4)
            Text(block.riskLevel.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(block.riskLevel.fillColor.opacity(0.2), in: Capsule())
                .foregroundStyle(block.riskLevel.fillColor)
        }
    }

    private func locationLabelRow(block: VineyardDemoBlock) -> some View {
        HStack(spacing: 5) {
            Text(block.locationLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let connection = block.sensorConnection {
                Circle()
                    .fill(connection.isOnline ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(connection.isOnline ? "Online" : "Offline")
            }
        }
    }

    private func metricCard(
        _ title: String,
        value: String,
        icon: String,
        tint: Color,
        source: ReadingDataSource
    ) -> some View {
        let background = source == .sensor
            ? Color.green.opacity(0.16)
            : Color.blue.opacity(0.12)

        return VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.caption.weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: layout == .compact ? 56 : 50, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(source == .sensor ? Color.green.opacity(0.35) : Color.blue.opacity(0.25), lineWidth: 1)
        )
    }

    private func overviewTile(
        title: String,
        value: String,
        caption: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(layout == .compact ? .title2.bold() : .title.bold())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func format(_ value: Double, unit: String) -> String {
        if unit == "in" {
            return String(format: "%.2f %@", value, unit)
        }
        if unit == "°F" || unit == "°" {
            return String(format: "%.1f%@", value, unit)
        }
        if unit.contains("MJ") {
            return String(format: "%.1f %@", value, unit)
        }
        return String(format: "%.1f %@", value, unit)
    }
}
