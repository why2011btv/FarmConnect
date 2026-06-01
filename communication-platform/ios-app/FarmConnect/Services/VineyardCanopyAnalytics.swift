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

        items.append(
            VineyardBlockInsight(
                id: "\(block.id)-metrics",
                title: "Canopy metrics",
                message: "GDD (base 50°F, daily proxy): \(Int(analytics.gddBase50F)). VPD: \(String(format: "%.2f", analytics.vpdKPa)) kPa.",
                severity: "low"
            )
        )

        items.append(combinedMildewInsight(block: block, analytics: analytics, variety: variety))

        if variety != .notSpecified {
            items.append(
                VineyardBlockInsight(
                    id: "\(block.id)-variety",
                    title: "\(variety.displayName)",
                    message: varietyContextMessage(variety: variety, powdery: analytics.powderyMildewIndex, downy: analytics.downyMildewIndex),
                    severity: "low"
                )
            )
        }

        items.append(actionInsight(block: block, analytics: analytics, variety: variety))
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
                title: "What to do this week",
                message: regionalActionContext(peakRisk: high > 0 ? .high : (moderate > 0 ? .moderate : .low)) + " Tap a block for block-specific canopy data.",
                severity: high > 0 ? "high" : "medium"
            ),
            VineyardBlockInsight(
                id: "g3",
                title: "Sensor network",
                message: "All \(blocks.count) canopy nodes are online. Set grape variety per block under Edit blocks.",
                severity: "low"
            ),
        ]
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

    private static func combinedMildewInsight(
        block: VineyardDemoBlock,
        analytics: VineyardCanopyAnalyticsSummary,
        variety: GrapeVariety
    ) -> VineyardBlockInsight {
        let powdery = Int(Double(analytics.powderyMildewIndex) * (0.85 + variety.powderySusceptibility * 0.15))
        let downy = Int(Double(analytics.downyMildewIndex) * (0.85 + variety.downySusceptibility * 0.15))
        let peak = max(powdery, downy)
        let severity = peak >= 70 ? "high" : (peak >= 40 ? "medium" : "low")

        let message: String
        switch peak {
        case 70...:
            message = """
            Powdery index \(powdery) (\(riskLabel(for: powdery))) and downy index \(downy) (\(riskLabel(for: downy))). \
            Canopy is warm and humid with limited airflow—scout leaves and plan a protectant spray if forecast stays damp.
            """
        case 40..<70:
            message = """
            Powdery index \(powdery) and downy index \(downy)—moderate pressure. \
            Watch overnight humidity and leaf wetness; spray only if wet weather is expected.
            """
        default:
            message = """
            Powdery index \(powdery) and downy index \(downy)—low pressure for now. \
            Conditions are not highly favorable for new mildew infections.
            """
        }

        return VineyardBlockInsight(
            id: "\(block.id)-mildew",
            title: "Mildew risk",
            message: message,
            severity: severity
        )
    }

    private static func varietyContextMessage(variety: GrapeVariety, powdery: Int, downy: Int) -> String {
        if powdery >= 60 || downy >= 60 {
            return "\(variety.displayName) tends toward higher mildew sensitivity—weight scouting accordingly."
        }
        return "\(variety.displayName) is on file for variety-aware recommendations."
    }

    private static func actionInsight(
        block: VineyardDemoBlock,
        analytics: VineyardCanopyAnalyticsSummary,
        variety: GrapeVariety
    ) -> VineyardBlockInsight {
        let risk = VineyardDemoData.riskLevel(from: analytics)
        let weatherNote = regionalActionContext(peakRisk: risk)
        let varietyNote = variety == .notSpecified ? "" : " (\(variety.displayName) block.)"

        let message: String
        let severity: String
        switch risk {
        case .high:
            message = "Apply fungicide in \(block.name) when wind is below 10 mph and before the next rain.\(varietyNote) \(weatherNote)"
            severity = "high"
        case .moderate:
            message = "Routine scouting in \(block.name); hold spray unless rain and humid nights continue.\(varietyNote) \(weatherNote)"
            severity = "medium"
        case .low:
            message = "No spray needed in \(block.name) based on current canopy readings; keep monitoring.\(varietyNote) \(weatherNote)"
            severity = "low"
        }

        return VineyardBlockInsight(
            id: "\(block.id)-action",
            title: "Recommended action",
            message: message,
            severity: severity
        )
    }

    /// Demo regional context (South Coast MA)—action only, no forecast UI.
    private static func regionalActionContext(peakRisk: VineyardRiskLevel) -> String {
        switch peakRisk {
        case .high:
            return "Outlook: humid nights and a chance of light rain in the next 48 h favor downy mildew in wet blocks—treat before weather closes spray windows."
        case .moderate:
            return "Outlook: a few mild, humid nights ahead; delay irrigation late in the day to limit leaf wetness."
        case .low:
            return "Outlook: drier, breezier pattern expected—favorable for holding off fungicide unless forecast changes."
        }
    }
}
