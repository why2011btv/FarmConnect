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
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]

        return VStack(alignment: .leading, spacing: 8) {
            compactHeader(for: block)

            LazyVGrid(columns: columns, spacing: 6) {
                compactMetricCard("Air temp", value: format(r.airTemperatureF, unit: "°F"), icon: "thermometer.medium", tint: .orange)
                compactMetricCard("Humidity", value: format(r.relativeHumidityPct, unit: "%"), icon: "humidity.fill", tint: .blue)
                compactMetricCard("Leaf wet", value: format(r.leafWetnessHours, unit: "h"), icon: "drop.fill", tint: .teal)
                compactMetricCard("Soil moist", value: format(r.soilMoisturePct, unit: "%"), icon: "drop.circle.fill", tint: .brown)
                compactMetricCard("Soil temp", value: format(r.soilTemperatureF, unit: "°F"), icon: "thermometer.sun.fill", tint: .orange)
                compactMetricCard("Rain 24h", value: format(r.rainfallInches24h, unit: "in"), icon: "cloud.rain.fill", tint: .indigo)
                compactMetricCard("Solar", value: format(r.solarExposureMJ, unit: "MJ/m²"), icon: "sun.max.fill", tint: .yellow)
                compactMetricCard("Wind", value: format(r.windSpeedMph, unit: "mph"), icon: "wind", tint: .cyan)
                compactMetricCard(
                    "Wind dir",
                    value: "\(r.windDirectionLabel) \(Int(r.windDirectionDegrees))°",
                    icon: "location.north.fill",
                    tint: .mint
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var vineyardOverview: some View {
        let summaryBlocks = allBlocks.isEmpty ? [] : allBlocks
        let highRisk = summaryBlocks.filter { $0.riskLevel == .high }.count
        let online = summaryBlocks.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Vineyard overview")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Tap a block on the map to view canopy microclimate readings and block-specific recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
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
            .padding()
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var riskSummaryRow: some View {
        let low = allBlocks.filter { $0.riskLevel == .low }.count
        let moderate = allBlocks.filter { $0.riskLevel == .moderate }.count
        let high = allBlocks.filter { $0.riskLevel == .high }.count

        return VStack(alignment: .leading, spacing: 8) {
            Text("Crop health summary")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                riskChip(count: low, label: "Low", color: .green)
                riskChip(count: moderate, label: "Moderate", color: .orange)
                riskChip(count: high, label: "High", color: .red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func riskChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func compactHeader(for block: VineyardDemoBlock) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.name)
                    .font(.subheadline.weight(.semibold))
                Text(block.locationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(block.riskLevel.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(block.riskLevel.fillColor.opacity(0.2), in: Capsule())
                .foregroundStyle(block.riskLevel.fillColor)
        }
    }

    private func compactMetricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.caption.weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
