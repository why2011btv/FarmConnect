import CoreLocation
import Foundation
import MapKit

/// Bundled demo vineyard data (Bristol County, MA coordinates). Generic labels in UI.
enum VineyardDemoData {
    static let mapCenter = CLLocationCoordinate2D(latitude: 41.68245, longitude: -71.00075)
    static let mapSpan = MKCoordinateSpan(latitudeDelta: 0.0065, longitudeDelta: 0.0045)

    /// Default rectangles aligned to Running Brook vineyard blocks (manual satellite fit).
    static let defaultRectangles: [VineyardBlockRectangle] = [
        rect("b1", 41.684619999999924, -71.00101000000005, halfLat: 0.00023500000000000007, halfLng: 0.0010950000000000016, rotation: 6.5),
        rect("b2", 41.68409999999994, -71.00093000000003, halfLat: 0.00026500000000000004, halfLng: 0.0010800000000000015, rotation: 6.5),
        rect("b3", 41.68349999999995, -71.00089000000001, halfLat: 0.000295, halfLng: 0.0009450000000000012, rotation: 7),
        rect("b4", 41.68260999999994, -71.00036999999975, halfLat: 0.0006050000000000002, halfLng: 0.00036499999999999993, rotation: 1),
        rect("b5", 41.68254999999994, -71.00113000000022, halfLat: 0.0005149999999999999, halfLng: 0.00036499999999999993, rotation: 0.5),
        rect("b6", 41.68154999999992, -71.00046999999988, halfLat: 0.0003549999999999999, halfLng: 0.00047499999999999984, rotation: 0),
        rect("b7", 41.68092999999992, -71.00044999999987, halfLat: 0.00025, halfLng: 0.0004899999999999999, rotation: 0),
        rect("b8", 41.68020999999992, -71.00044999999987, halfLat: 0.0004299999999999998, halfLng: 0.0005049999999999999, rotation: 0),
    ]

    static let generalInsights: [VineyardBlockInsight] = [
        insight(
            "g1",
            "Vineyard-wide disease outlook",
            "5 of 8 canopy blocks are in the low-risk band; Blocks 4 and 6 are moderate. Block 3 is high—prioritize scouting and spray timing there.",
            "high"
        ),
        insight(
            "g2",
            "Spraying and harvesting",
            "A protectant fungicide application is recommended in high-risk blocks within 48 hours if conditions remain humid. Harvest timing is not constrained by current heat or moisture stress.",
            "medium"
        ),
        insight(
            "g3",
            "Weather pattern",
            "Recent light rainfall increased canopy moisture in Block 3. Blocks with good air drainage and lower humidity (1, 2, 5, 7, 8) remain in the low-risk zone.",
            "low"
        ),
        insight(
            "g4",
            "Sensor network status",
            "All 8 canopy nodes are reporting. Tap a block on the map to view block-level microclimate readings and tailored recommendations.",
            "low"
        ),
    ]

    static let defaultBlockSettings: [String: VineyardBlockSettings] = [
        "b1": VineyardBlockSettings(grapeVariety: GrapeVariety.cabernetFranc.rawValue),
        "b2": VineyardBlockSettings(grapeVariety: GrapeVariety.merlot.rawValue),
        "b3": VineyardBlockSettings(grapeVariety: GrapeVariety.pinotGris.rawValue),
        "b4": VineyardBlockSettings(grapeVariety: GrapeVariety.merlot.rawValue),
        "b5": VineyardBlockSettings(grapeVariety: GrapeVariety.chardonnay.rawValue),
        "b6": VineyardBlockSettings(grapeVariety: GrapeVariety.cabernetFranc.rawValue),
        "b7": VineyardBlockSettings(grapeVariety: GrapeVariety.pinotGris.rawValue),
        "b8": VineyardBlockSettings(grapeVariety: GrapeVariety.riesling.rawValue),
    ]

    static func makeBlocks(
        rectangles: [VineyardBlockRectangle],
        settings: [String: VineyardBlockSettings] = defaultBlockSettings
    ) -> [VineyardDemoBlock] {
        var blocks: [VineyardDemoBlock] = []
        for (index, rectangle) in rectangles.enumerated() {
            // Curated demo blocks (b1..b8) use their hand-authored readings; auto-generated
            // blocks (e.g. "gen-1") get a deterministic synthetic template so they still
            // render with a believable risk spread in Planning mode.
            let template = blockTemplates[rectangle.id] ?? syntheticTemplate(id: rectangle.id, index: index)
            let variety = settings[rectangle.id]?.variety ?? .notSpecified
            let analytics = VineyardCanopyAnalytics.summarize(readings: template.readings)
            let risk = riskLevel(from: analytics)

            let draft = VineyardDemoBlock(
                id: rectangle.id,
                name: template.name,
                locationLabel: template.locationLabel,
                polygon: rectangle.polygon,
                center: rectangle.center,
                riskLevel: risk,
                readings: template.readings,
                grapeVariety: variety,
                analytics: analytics,
                insights: []
            )
            let insights = VineyardCanopyAnalytics.insights(for: draft)
            blocks.append(
                VineyardDemoBlock(
                    id: draft.id,
                    name: draft.name,
                    locationLabel: draft.locationLabel,
                    polygon: draft.polygon,
                    center: draft.center,
                    riskLevel: draft.riskLevel,
                    readings: draft.readings,
                    grapeVariety: draft.grapeVariety,
                    analytics: draft.analytics,
                    insights: insights
                )
            )
        }
        return blocks
    }

    static func riskLevel(from analytics: VineyardCanopyAnalyticsSummary) -> VineyardRiskLevel {
        let peak = max(analytics.powderyMildewIndex, analytics.downyMildewIndex)
        switch peak {
        case 70...: return .high
        case 40..<70: return .moderate
        default: return .low
        }
    }

    static var mapRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: mapCenter, span: mapSpan)
    }

    /// The curated, farmer-facing layout shipped out of the box (hand-tuned Running Brook blocks).
    static var defaultDemoSlot: LayoutSlot {
        LayoutSlot(rectangles: defaultRectangles, blockSettings: defaultBlockSettings, profile: nil)
    }

    // MARK: - Block metadata (readings / risk do not depend on map position)

    private struct BlockTemplate {
        let name: String
        let locationLabel: String
        let readings: VineyardCanopyReading
    }

    private static let blockTemplates: [String: BlockTemplate] = [
        "b1": template(
            name: "Block 1",
            locationLabel: "North rows (upper)",
            readings: readings(
                temp: 78, rh: 52, leafWet: 0.4, soilMoist: 39, soilTemp: 70,
                rain: 0.01, solar: 24, wind: 10, windDir: 240
            )
        ),
        "b2": template(
            name: "Block 2",
            locationLabel: "North rows (middle)",
            readings: readings(
                temp: 77, rh: 53, leafWet: 0.6, soilMoist: 41, soilTemp: 69,
                rain: 0.02, solar: 23, wind: 9, windDir: 210
            )
        ),
        "b3": template(
            name: "Block 3",
            locationLabel: "North rows (lower)",
            readings: readings(
                temp: 72, rh: 88, leafWet: 6.2, soilMoist: 48, soilTemp: 68,
                rain: 0.14, solar: 17, wind: 2.5, windDir: 55
            )
        ),
        "b4": template(
            name: "Block 4",
            locationLabel: "Middle section (west)",
            readings: readings(
                temp: 74, rh: 66, leafWet: 2.2, soilMoist: 44, soilTemp: 68,
                rain: 0.04, solar: 20, wind: 6.5, windDir: 70
            )
        ),
        "b5": template(
            name: "Block 5",
            locationLabel: "Middle section (east)",
            readings: readings(
                temp: 79, rh: 50, leafWet: 0.3, soilMoist: 36, soilTemp: 71,
                rain: 0.0, solar: 25, wind: 11, windDir: 255
            )
        ),
        "b6": template(
            name: "Block 6",
            locationLabel: "South rows (upper)",
            readings: readings(
                temp: 76, rh: 64, leafWet: 2.4, soilMoist: 41, soilTemp: 69,
                rain: 0.03, solar: 21, wind: 7, windDir: 225
            )
        ),
        "b7": template(
            name: "Block 7",
            locationLabel: "South rows (middle)",
            readings: readings(
                temp: 75, rh: 52, leafWet: 0.8, soilMoist: 40, soilTemp: 69,
                rain: 0.02, solar: 22, wind: 8, windDir: 90
            )
        ),
        "b8": template(
            name: "Block 8",
            locationLabel: "South rows (lower)",
            readings: readings(
                temp: 76, rh: 53, leafWet: 0.5, soilMoist: 38, soilTemp: 70,
                rain: 0.01, solar: 23, wind: 9, windDir: 265
            )
        ),
    ]

    // MARK: - Helpers

    private static func rect(
        _ id: String,
        _ lat: Double,
        _ lng: Double,
        halfLat: Double,
        halfLng: Double,
        rotation: Double = 0
    ) -> VineyardBlockRectangle {
        VineyardBlockRectangle(
            id: id,
            centerLatitude: lat,
            centerLongitude: lng,
            halfLatitudeSpan: halfLat,
            halfLongitudeSpan: halfLng,
            rotationDegrees: rotation
        )
    }

    private static func template(
        name: String,
        locationLabel: String,
        readings: VineyardCanopyReading
    ) -> BlockTemplate {
        BlockTemplate(name: name, locationLabel: locationLabel, readings: readings)
    }

    private static func readings(
        temp: Double, rh: Double, leafWet: Double, soilMoist: Double, soilTemp: Double,
        rain: Double, solar: Double, wind: Double, windDir: Double
    ) -> VineyardCanopyReading {
        VineyardCanopyReading(
            airTemperatureF: temp,
            relativeHumidityPct: rh,
            leafWetnessHours: leafWet,
            soilMoisturePct: soilMoist,
            soilTemperatureF: soilTemp,
            rainfallInches24h: rain,
            solarExposureMJ: solar,
            windSpeedMph: wind,
            windDirectionDegrees: windDir
        )
    }

    private static func insight(
        _ id: String,
        _ title: String,
        _ message: String,
        _ severity: String
    ) -> VineyardBlockInsight {
        VineyardBlockInsight(id: id, title: title, message: message, severity: severity)
    }

    // MARK: - Synthetic templates for auto-generated blocks

    /// Deterministic, plausible readings for an auto-generated block id (e.g. "gen-3").
    /// Seeded by a STABLE hash of the id (never `String.hashValue`, which is randomized per
    /// launch and would make Planning-mode readings/risk flicker on every app start).
    private static func syntheticTemplate(id: String, index: Int) -> BlockTemplate {
        let seed = stableHash(id)
        // Map the seed onto [0, 1) for repeatable pseudo-variation.
        let t = Double(seed % 1000) / 1000.0
        let t2 = Double((seed / 1000) % 1000) / 1000.0

        // Spread readings so the auto-arranged layout shows a realistic mix of low/moderate/high
        // risk (peak mildew index <40 low, 40–69 moderate, ≥70 high — see VineyardCanopyAnalytics).
        let temp = 70 + t * 12               // 70–82°F (within the 60–85 powdery-favorable band)
        let rh = 48 + t2 * 42                // 48–90% RH
        let leafWet = (t2 > 0.6) ? (t2 - 0.6) * 12 : 0.3   // mostly dry, occasionally wet
        let soilMoist = 36 + t * 14          // 36–50%
        let soilTemp = 66 + t2 * 6           // 66–72°F
        let rain = (t > 0.7) ? (t - 0.7) * 0.4 : 0.0
        let solar = 16 + (1 - t2) * 9        // 16–25 MJ
        let wind = 2 + t * 9                 // 2–11 mph
        let windDir = Double((seed / 7) % 360)

        return BlockTemplate(
            name: "Block \(index + 1)",
            locationLabel: "Auto-placed zone \(index + 1)",
            readings: readings(
                temp: temp, rh: rh, leafWet: leafWet, soilMoist: soilMoist, soilTemp: soilTemp,
                rain: rain, solar: solar, wind: wind, windDir: windDir
            )
        )
    }

    /// Stable, launch-independent hash of a string (FNV-1a, 32-bit, folded to non-negative).
    private static func stableHash(_ string: String) -> Int {
        var hash: UInt32 = 2166136261
        for byte in string.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return Int(hash & 0x7FFF_FFFF)
    }
}
