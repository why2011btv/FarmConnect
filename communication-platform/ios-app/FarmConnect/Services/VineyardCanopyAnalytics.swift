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

    static func insights(
        for block: VineyardDemoBlock,
        analytics: VineyardCanopyAnalyticsSummary
    ) -> [VineyardBlockInsight] {
        let variety = block.grapeVariety
        var items: [VineyardBlockInsight] = []

        items.append(
            VineyardBlockInsight(
                id: "\(block.id)-analytics",
                title: "Canopy analytics",
                message: """
                GDD (base 50°F, daily proxy): \(Int(analytics.gddBase50F)) · \
                VPD: \(String(format: "%.2f", analytics.vpdKPa)) kPa · \
                Powdery index: \(analytics.powderyMildewIndex) (\(analytics.powderyRiskLabel)) · \
                Downy index: \(analytics.downyMildewIndex) (\(analytics.downyRiskLabel)).
                """,
                severity: "low"
            )
        )

        items.append(powderyInsight(blockId: block.id, readings: block.readings, index: analytics.powderyMildewIndex, variety: variety))
        items.append(downyInsight(blockId: block.id, readings: block.readings, index: analytics.downyMildewIndex, variety: variety))

        if variety != .notSpecified {
            items.append(
                VineyardBlockInsight(
                    id: "\(block.id)-variety",
                    title: "\(variety.displayName) block",
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

        let highPowdery = blocks.filter { summarize(readings: $0.readings).powderyMildewIndex >= 70 }.count
        let highDowny = blocks.filter { summarize(readings: $0.readings).downyMildewIndex >= 70 }.count
        let avgGDD = blocks.map { summarize(readings: $0.readings).gddBase50F }.reduce(0, +) / Double(blocks.count)

        return [
            VineyardBlockInsight(
                id: "g1",
                title: "Vineyard-wide disease outlook",
                message: "\(highPowdery) block(s) show elevated powdery pressure and \(highDowny) show elevated downy pressure. Prioritize blocks with index ≥ 70 for scouting and fungicide timing.",
                severity: (highPowdery + highDowny) > 0 ? "high" : "low"
            ),
            VineyardBlockInsight(
                id: "g2",
                title: "Growing degree days",
                message: "Average canopy GDD proxy (base 50°F) across nodes is \(Int(avgGDD)). Use block-level GDD with variety and phenology for spray and harvest planning.",
                severity: "low"
            ),
            VineyardBlockInsight(
                id: "g3",
                title: "Mildew-friendly conditions",
                message: "Powdery mildew favors warm canopy (60–85°F) with sustained humidity; downy favors leaf wetness > 4 h, RH > 85%, and recent rain with calm wind.",
                severity: "medium"
            ),
            VineyardBlockInsight(
                id: "g4",
                title: "Sensor network",
                message: "All \(blocks.count) canopy nodes are reporting. Set grape variety per block under Edit blocks for variety-aware recommendations.",
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

    /// 0–100; higher = more favorable for powdery mildew.
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

    /// 0–100; higher = more favorable for downy mildew.
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

    private static func powderyInsight(
        blockId: String,
        readings: VineyardCanopyReading,
        index: Int,
        variety: GrapeVariety
    ) -> VineyardBlockInsight {
        let adjusted = Int(Double(index) * (0.85 + variety.powderySusceptibility * 0.15))
        let severity = adjusted >= 70 ? "high" : (adjusted >= 40 ? "medium" : "low")
        let message: String
        if adjusted >= 70 {
            message = "Warm canopy (\(Int(readings.airTemperatureF))°F) with RH \(Int(readings.relativeHumidityPct))% supports powdery mildew. Scout young leaves and consider sulfur or targeted fungicide per label."
        } else if adjusted >= 40 {
            message = "Humidity and temperature are in a range where powdery can develop—monitor over the next 48 hours if nights stay humid."
        } else {
            message = "Current temperature and humidity are less favorable for powdery mildew establishment."
        }
        return VineyardBlockInsight(
            id: "\(blockId)-powdery",
            title: "Powdery mildew pressure",
            message: message,
            severity: severity
        )
    }

    private static func downyInsight(
        blockId: String,
        readings: VineyardCanopyReading,
        index: Int,
        variety: GrapeVariety
    ) -> VineyardBlockInsight {
        let adjusted = Int(Double(index) * (0.85 + variety.downySusceptibility * 0.15))
        let severity = adjusted >= 70 ? "high" : (adjusted >= 40 ? "medium" : "low")
        let message: String
        if adjusted >= 70 {
            message = "Leaf wetness \(String(format: "%.1f", readings.leafWetnessHours)) h, RH \(Int(readings.relativeHumidityPct))%, and recent rain favor downy mildew. A protectant spray within 48 h may be warranted."
        } else if adjusted >= 40 {
            message = "Extended leaf wetness or high RH—watch forecast; downy risk rises with overnight dew and calm wind."
        } else {
            message = "Leaf wetness and humidity are below typical downy infection thresholds for now."
        }
        return VineyardBlockInsight(
            id: "\(blockId)-downy",
            title: "Downy mildew pressure",
            message: message,
            severity: severity
        )
    }

    private static func varietyContextMessage(variety: GrapeVariety, powdery: Int, downy: Int) -> String {
        let powderyNote = powdery >= 60 ? "relatively susceptible to powdery mildew" : "moderate powdery sensitivity"
        let downyNote = downy >= 60 ? "elevated downy risk in wet periods" : "typical downy monitoring advised"
        return "\(variety.displayName) is \(powderyNote) and warrants \(downyNote). Future AI recommendations will weight this variety."
    }

    private static func actionInsight(
        block: VineyardDemoBlock,
        analytics: VineyardCanopyAnalyticsSummary,
        variety: GrapeVariety
    ) -> VineyardBlockInsight {
        let maxIndex = max(analytics.powderyMildewIndex, analytics.downyMildewIndex)
        let varietySuffix = variety == .notSpecified ? " Set grape variety in Edit blocks for tailored guidance." : ""

        if maxIndex >= 70 {
            return VineyardBlockInsight(
                id: "\(block.id)-action",
                title: "Recommended action",
                message: "Schedule fungicide when wind < 10 mph and before the next rain event; prioritize canopy penetration in \(block.name).\(varietySuffix)",
                severity: "high"
            )
        }
        if maxIndex >= 40 {
            return VineyardBlockInsight(
                id: "\(block.id)-action",
                title: "Recommended action",
                message: "Continue routine scouting; no immediate spray required unless forecast shows prolonged wetting.\(varietySuffix)",
                severity: "medium"
            )
        }
        return VineyardBlockInsight(
            id: "\(block.id)-action",
            title: "Recommended action",
            message: "Conditions are unfavorable for new mildew infections; maintain monitoring.\(varietySuffix)",
            severity: "low"
        )
    }
}
