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
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]

        return VStack(alignment: .leading, spacing: 12) {
            blockHeader(for: block)

            LazyVGrid(columns: columns, spacing: 10) {
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
            .frame(maxHeight: .infinity, alignment: .top)

            Spacer(minLength: 0)
        }
        .padding(16)
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

            Spacer(minLength: 0)
        }
        .padding(16)
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

    private func blockHeader(for block: VineyardDemoBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(block.name)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(block.riskLevel.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
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
                .font(.body.weight(.semibold))
                .minimumScaleFactor(0.75)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
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
