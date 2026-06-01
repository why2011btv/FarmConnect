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
            "3 of 8 canopy blocks show elevated powdery or downy mildew risk based on humidity, leaf wetness, and airflow. Focus scouting on Blocks 3, 4, and 7.",
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
            "Recent light rainfall and calm overnight winds increased canopy moisture in eastern and western rows. Blocks with good air drainage (1, 5, 8) remain in the low-risk zone.",
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
        for rectangle in rectangles {
            guard let template = blockTemplates[rectangle.id] else { continue }
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
                temp: 74.2, rh: 58, leafWet: 0.6, soilMoist: 39, soilTemp: 69.5,
                rain: 0.02, solar: 22.4, wind: 8.2, windDir: 240
            )
        ),
        "b2": template(
            name: "Block 2",
            locationLabel: "North rows (middle)",
            readings: readings(
                temp: 73.8, rh: 72, leafWet: 2.8, soilMoist: 44, soilTemp: 68.8,
                rain: 0.08, solar: 20.1, wind: 5.4, windDir: 210
            )
        ),
        "b3": template(
            name: "Block 3",
            locationLabel: "North rows (lower)",
            readings: readings(
                temp: 72.4, rh: 88, leafWet: 6.2, soilMoist: 48, soilTemp: 67.9,
                rain: 0.14, solar: 17.6, wind: 2.8, windDir: 55
            )
        ),
        "b4": template(
            name: "Block 4",
            locationLabel: "Middle section (west)",
            readings: readings(
                temp: 71.9, rh: 86, leafWet: 5.4, soilMoist: 46, soilTemp: 67.2,
                rain: 0.12, solar: 18.2, wind: 3.1, windDir: 70
            )
        ),
        "b5": template(
            name: "Block 5",
            locationLabel: "Middle section (east)",
            readings: readings(
                temp: 75.1, rh: 55, leafWet: 0.4, soilMoist: 36, soilTemp: 70.8,
                rain: 0.01, solar: 23.8, wind: 9.6, windDir: 255
            )
        ),
        "b6": template(
            name: "Block 6",
            locationLabel: "South rows (upper)",
            readings: readings(
                temp: 74.6, rh: 68, leafWet: 3.1, soilMoist: 41, soilTemp: 69.9,
                rain: 0.05, solar: 21.3, wind: 6.0, windDir: 225
            )
        ),
        "b7": template(
            name: "Block 7",
            locationLabel: "South rows (middle)",
            readings: readings(
                temp: 72.8, rh: 84, leafWet: 4.9, soilMoist: 47, soilTemp: 68.1,
                rain: 0.11, solar: 16.9, wind: 3.5, windDir: 90
            )
        ),
        "b8": template(
            name: "Block 8",
            locationLabel: "South rows (lower)",
            readings: readings(
                temp: 74.9, rh: 61, leafWet: 1.1, soilMoist: 38, soilTemp: 70.2,
                rain: 0.03, solar: 22.0, wind: 7.8, windDir: 265
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
}
