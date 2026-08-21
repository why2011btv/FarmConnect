import Foundation

struct VineyardCanopyAnalyticsSummary {
    let gddBase50F: Double
    let vpdKPa: Double
    let powderyMildewIndex: Int
    let downyMildewIndex: Int
    let powderyRiskLabel: String
    let downyRiskLabel: String
}

enum VineyardCanopyAnalytics {
    private static let gddBaseF = 50.0

    static func summarize(readings: VineyardCanopyReading) -> VineyardCanopyAnalyticsSummary {
        let powdery = powderyMildewIndex(readings: readings)
        let downy = downyMildewIndex(readings: readings)
        return VineyardCanopyAnalyticsSummary(
            gddBase50F: gddDailyProxy(tempF: readings.airTemperatureF),
            vpdKPa: vaporPressureDeficitKPa(tempF: readings.airTemperatureF, rhPct: readings.relativeHumidityPct),
            powderyMildewIndex: powdery,
            downyMildewIndex: downy,
            powderyRiskLabel: riskLabel(for: powdery),
            downyRiskLabel: riskLabel(for: downy)
        )
    }

    static func insights(for block: VineyardDemoBlock) -> [VineyardBlockInsight] {
        let analytics = block.analytics
        let variety = block.grapeVariety
        var items: [VineyardBlockInsight] = []

        // Block-level microclimate context only. Disease infection risk is now computed from the
        // validated models in the "Disease risk" view (Spotts/Gubler-Thomas/Erincik/DMCast), not the
        // earlier invented indices.
        items.append(
            VineyardBlockInsight(
                id: "\(block.id)-metrics",
                title: "Canopy conditions",
                message: "Vapor-pressure deficit: \(String(format: "%.2f", analytics.vpdKPa)) kPa — a measure of how drying the air is at the canopy.",
                severity: "low"
            )
        )

        if variety != .notSpecified {
            items.append(
                VineyardBlockInsight(
                    id: "\(block.id)-variety",
                    title: "\(variety.displayName)",
                    message: "\(variety.displayName) is on file for variety-aware notes.",
                    severity: "low"
                )
            )
        }

        items.append(
            VineyardBlockInsight(
                id: "\(block.id)-disease-pointer",
                title: "Disease infection risk",
                message: "See “Disease risk” for validated, weather-based infection-condition estimates (black rot, Phomopsis, powdery, downy). Scouting decision support — not a spray recommendation.",
                severity: "low"
            )
        )
        return items
    }

    static func vineyardWideInsights(blocks: [VineyardDemoBlock]) -> [VineyardBlockInsight] {
        guard !blocks.isEmpty else { return VineyardDemoData.generalInsights }

        let low = blocks.filter { $0.riskLevel == .low }.count
        let moderate = blocks.filter { $0.riskLevel == .moderate }.count
        let high = blocks.filter { $0.riskLevel == .high }.count
        let highRiskNames = blocks.filter { $0.riskLevel == .high }.map(\.name).joined(separator: ", ")

        return [
            VineyardBlockInsight(
                id: "g1",
                title: "Vineyard-wide outlook",
                message: "Crop health: \(low) low, \(moderate) moderate, \(high) high. \(high > 0 ? "Priority: \(highRiskNames)." : "No blocks in the high-risk band right now.")",
                severity: high > 0 ? "high" : "low"
            ),
            VineyardBlockInsight(
                id: "g2",
                title: "Where to focus",
                message: (high > 0
                    ? "\(high) block\(high == 1 ? "" : "s") show conditions that favor infection — scout those first and check your fungicide program and the product label."
                    : (moderate > 0
                        ? "Moderate pressure in some blocks — scout and watch overnight leaf wetness."
                        : "Low infection pressure across blocks right now — keep scouting."))
                    + " Tap a block for its readings.",
                severity: high > 0 ? "high" : "medium"
            ),
            VineyardBlockInsight(
                id: "g3",
                title: "Sensor network",
                message: sensorNetworkMessage(blocks: blocks),
                severity: "low"
            ),
        ]
    }

    private static func sensorNetworkMessage(blocks: [VineyardDemoBlock]) -> String {
        let live = blocks.filter { $0.liveSensor != nil }.count
        if live > 0 {
            return "\(live) block\(live == 1 ? "" : "s") include live field-sensor readings; other metrics use local weather for each block."
        }
        return "Blocks use local weather at each block's coordinates. Demo blocks 1–2 also listen for field sensors."
    }

    // MARK: - Indices

    private static func gddDailyProxy(tempF: Double) -> Double {
        max(0, tempF - gddBaseF)
    }

    private static func vaporPressureDeficitKPa(tempF: Double, rhPct: Double) -> Double {
        let tempC = (tempF - 32) * 5.0 / 9.0
        let svp = 0.6108 * exp((17.27 * tempC) / (tempC + 237.3))
        return svp * (1 - rhPct / 100)
    }

    private static func powderyMildewIndex(readings: VineyardCanopyReading) -> Int {
        var score = 0.0
        let temp = readings.airTemperatureF
        let rh = readings.relativeHumidityPct

        if temp >= 60, temp <= 85 { score += 35 }
        if rh >= 50 { score += min(35, (rh - 50) * 1.2) }
        if readings.leafWetnessHours < 2, rh >= 65 { score += 15 }
        if readings.windSpeedMph < 6 { score += 10 }
        if readings.solarExposureMJ < 18 { score += 5 }

        return Int(min(100, score.rounded()))
    }

    private static func downyMildewIndex(readings: VineyardCanopyReading) -> Int {
        var score = 0.0
        let temp = readings.airTemperatureF
        let rh = readings.relativeHumidityPct

        if rh >= 75 { score += min(35, (rh - 75) * 2.0 + 20) }
        if readings.leafWetnessHours >= 2 { score += min(40, readings.leafWetnessHours * 6) }
        if readings.rainfallInches24h >= 0.05 { score += 20 }
        if temp >= 60, temp <= 78 { score += 15 }
        if readings.windSpeedMph < 5 { score += 10 }

        return Int(min(100, score.rounded()))
    }

    private static func riskLabel(for index: Int) -> String {
        switch index {
        case 70...: return "High"
        case 40..<70: return "Moderate"
        default: return "Low"
        }
    }




}
