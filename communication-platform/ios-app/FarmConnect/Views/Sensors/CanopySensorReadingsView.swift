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
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(for: block)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metricCard("Air temperature", value: format(r.airTemperatureF, unit: "°F"), icon: "thermometer.medium", tint: .orange)
                    metricCard("Relative humidity", value: format(r.relativeHumidityPct, unit: "%"), icon: "humidity.fill", tint: .blue)
                    metricCard("Leaf wetness", value: format(r.leafWetnessHours, unit: "h"), icon: "drop.fill", tint: .teal)
                    metricCard("Soil moisture", value: format(r.soilMoisturePct, unit: "%"), icon: "drop.circle.fill", tint: .brown)
                    metricCard("Soil temperature", value: format(r.soilTemperatureF, unit: "°F"), icon: "thermometer.sun.fill", tint: .orange)
                    metricCard("Rainfall (24h)", value: format(r.rainfallInches24h, unit: "in"), icon: "cloud.rain.fill", tint: .indigo)
                    metricCard("Solar exposure", value: format(r.solarExposureMJ, unit: "MJ/m²"), icon: "sun.max.fill", tint: .yellow)
                    metricCard("Wind speed", value: format(r.windSpeedMph, unit: "mph"), icon: "wind", tint: .cyan)
                    metricCard(
                        "Wind direction",
                        value: "\(r.windDirectionLabel) (\(Int(r.windDirectionDegrees))°)",
                        icon: "location.north.fill",
                        tint: .mint
                    )
                }
            }
            .padding()
        }
        .scrollBounceBehavior(.basedOnSize)
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

    private func header(for block: VineyardDemoBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(block.name)
                    .font(.headline)
                Spacer()
                Text(block.riskLevel.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(block.riskLevel.fillColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(block.riskLevel.fillColor)
            }
            Text(block.locationLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func metricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.title3.bold())
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
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
