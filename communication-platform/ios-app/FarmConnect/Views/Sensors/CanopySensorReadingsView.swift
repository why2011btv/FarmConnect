import SwiftUI

struct CanopySensorReadingsView: View {
    let block: VineyardDemoBlock?
    var allBlocks: [VineyardDemoBlock] = []

    var body: some View {
        Group {
            if let block {
                blockReadings(block)
            } else {
                vineyardOverview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func blockReadings(_ block: VineyardDemoBlock) -> some View {
        let r = block.readings
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            compactBlockHeader(for: block)

            LazyVGrid(columns: columns, spacing: 8) {
                metricCard("Air temp", value: format(r.airTemperatureF, unit: "°F"), icon: "thermometer.medium", tint: .orange)
                metricCard("Humidity", value: format(r.relativeHumidityPct, unit: "%"), icon: "humidity.fill", tint: .blue)
                metricCard("Leaf wet", value: format(r.leafWetnessHours, unit: "h"), icon: "drop.fill", tint: .teal)
                metricCard("Soil moist", value: format(r.soilMoisturePct, unit: "%"), icon: "drop.circle.fill", tint: .brown)
                metricCard("Soil temp", value: format(r.soilTemperatureF, unit: "°F"), icon: "thermometer.sun.fill", tint: .orange)
                metricCard("Rain 24h", value: format(r.rainfallInches24h, unit: "in"), icon: "cloud.rain.fill", tint: .indigo)
                metricCard("Solar", value: format(r.solarExposureMJ, unit: "MJ/m²"), icon: "sun.max.fill", tint: .yellow)
                metricCard("Wind", value: format(r.windSpeedMph, unit: "mph"), icon: "wind", tint: .cyan)
                metricCard(
                    "Wind dir",
                    value: "\(r.windDirectionLabel) \(Int(r.windDirectionDegrees))°",
                    icon: "location.north.fill",
                    tint: .mint
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var vineyardOverview: some View {
        let summaryBlocks = allBlocks.isEmpty ? [] : allBlocks
        let highRisk = summaryBlocks.filter { $0.riskLevel == .high }.count
        let online = summaryBlocks.count

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Vineyard overview")
                    .font(.headline)
                Text("Tap a block on the map to view canopy readings and tailored recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                overviewTile(
                    title: "Canopy nodes",
                    value: "\(online)",
                    caption: "All online",
                    icon: "sensor.tag.radiowaves.forward.fill",
                    tint: .green
                )
                overviewTile(
                    title: "High-risk blocks",
                    value: "\(highRisk)",
                    caption: "Fungus pressure",
                    icon: "leaf.fill",
                    tint: .red
                )
            }

            riskSummaryRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var riskSummaryRow: some View {
        let low = allBlocks.filter { $0.riskLevel == .low }.count
        let moderate = allBlocks.filter { $0.riskLevel == .moderate }.count
        let high = allBlocks.filter { $0.riskLevel == .high }.count

        return VStack(alignment: .leading, spacing: 8) {
            Text("Crop health summary")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                riskChip(count: low, label: "Low", color: .green)
                riskChip(count: moderate, label: "Moderate", color: .orange)
                riskChip(count: high, label: "High", color: .red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func riskChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func compactBlockHeader(for block: VineyardDemoBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.name)
                        .font(.subheadline.weight(.semibold))
                    Text(block.locationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if block.grapeVariety != .notSpecified {
                        Text(block.grapeVariety.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
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

            Text(analyticsSummaryLine(block.analytics))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func analyticsSummaryLine(_ analytics: VineyardCanopyAnalyticsSummary) -> String {
        "GDD \(Int(analytics.gddBase50F)) · VPD \(String(format: "%.2f", analytics.vpdKPa)) kPa · Powdery \(analytics.powderyMildewIndex) · Downy \(analytics.downyMildewIndex)"
    }

    private func metricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func overviewTile(
        title: String,
        value: String,
        caption: String,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title.bold())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
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
