import CoreLocation
import Foundation
import MapKit

/// Bundled demo vineyard data (Bristol County, MA coordinates). Generic labels in UI.
enum VineyardDemoData {
    // Running Brook Vineyard area — used only for map framing, not shown by name.
    static let mapCenter = CLLocationCoordinate2D(latitude: 41.67914, longitude: -70.999375)
    static let mapSpan = MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.014)

    static let blocks: [VineyardDemoBlock] = [
        block(
            id: "b1",
            name: "Block 1",
            locationLabel: "Northwest canopy row",
            risk: .low,
            center: coord(41.68085, -71.00105),
            polygon: quad(
                (41.68155, -71.00175),
                (41.68155, -71.00035),
                (41.68015, -71.00035),
                (41.68015, -71.00175)
            ),
            readings: VineyardCanopyReading(
                airTemperatureF: 74.2,
                relativeHumidityPct: 58,
                leafWetnessHours: 0.6,
                soilMoisturePct: 39,
                soilTemperatureF: 69.5,
                rainfallInches24h: 0.02,
                solarExposureMJ: 22.4,
                windSpeedMph: 8.2,
                windDirectionDegrees: 240
            ),
            insights: [
                insight(
                    "b1-i1",
                    "Canopy conditions favorable",
                    "Humidity and leaf wetness are below thresholds for powdery and downy mildew development.",
                    "low"
                )
            ]
        ),
        block(
            id: "b2",
            name: "Block 2",
            locationLabel: "Northeast slope",
            risk: .moderate,
            center: coord(41.68085, -70.99770),
            polygon: quad(
                (41.68155, -70.99840),
                (41.68155, -70.99700),
                (41.68015, -70.99700),
                (41.68015, -70.99840)
            ),
            readings: VineyardCanopyReading(
                airTemperatureF: 73.8,
                relativeHumidityPct: 72,
                leafWetnessHours: 2.8,
                soilMoisturePct: 44,
                soilTemperatureF: 68.8,
                rainfallInches24h: 0.08,
                solarExposureMJ: 20.1,
                windSpeedMph: 5.4,
                windDirectionDegrees: 210
            ),
            insights: [
                insight(
                    "b2-i1",
                    "Monitor overnight humidity",
                    "Extended leaf wetness after dew may elevate downy mildew risk if RH stays above 75% tonight.",
                    "medium"
                )
            ]
        ),
        block(
            id: "b3",
            name: "Block 3",
            locationLabel: "East upper canopy",
            risk: .high,
            center: coord(41.67955, -70.99720),
            polygon: quad(
                (41.68025, -70.99790),
                (41.68025, -70.99650),
                (41.67885, -70.99650),
                (41.67885, -70.99790)
            ),
            readings: VineyardCanopyReading(
                airTemperatureF: 72.4,
                relativeHumidityPct: 88,
                leafWetnessHours: 6.2,
                soilMoisturePct: 48,
                soilTemperatureF: 67.9,
                rainfallInches24h: 0.14,
                solarExposureMJ: 17.6,
                windSpeedMph: 2.8,
                windDirectionDegrees: 55
            ),
            insights: [
                insight(
                    "b3-i1",
                    "Elevated downy mildew risk",
                    "High RH, recent rain, and low airflow in the canopy favor downy mildew. Consider a protectant spray within 48 hours.",
                    "high"
                ),
                insight(
                    "b3-i2",
                    "Leaf wetness accumulation",
                    "Canopy sensors logged over 6 hours of leaf wetness in the last 24 hours — above the typical infection threshold.",
                    "high"
                )
            ]
        ),
        block(
            id: "b4",
            name: "Block 4",
            locationLabel: "East lower canopy",
            risk: .high,
            center: coord(41.67815, -70.99720),
            polygon: quad(
                (41.67885, -70.99790),
                (41.67885, -70.99650),
                (41.67745, -70.99650),
                (41.67745, -70.99790)
            ),
            readings: VineyardCanopyReading(
                airTemperatureF: 71.9,
                relativeHumidityPct: 86,
                leafWetnessHours: 5.4,
                soilMoisturePct: 46,
                soilTemperatureF: 67.2,
                rainfallInches24h: 0.12,
                solarExposureMJ: 18.2,
                windSpeedMph: 3.1,
                windDirectionDegrees: 70
            ),
            insights: [
                insight(
                    "b4-i1",
                    "Powdery mildew pressure building",
                    "Warm canopy temperatures with sustained humidity support powdery mildew. Scout undersides of leaves on susceptible cultivars.",
                    "high"
                )
            ]
        ),
        block(
            id: "b5",
            name: "Block 5",
            locationLabel: "South central rows",
            risk: .low,
            center: coord(41.67745, -70.999375),
            polygon: quad(
                (41.67815, -71.00008),
                (41.67815, -70.99867),
                (41.67675, -70.99867),
                (41.67675, -71.00008)
            ),
            readings: VineyardCanopyReading(
                airTemperatureF: 75.1,
                relativeHumidityPct: 55,
                leafWetnessHours: 0.4,
                soilMoisturePct: 36,
                soilTemperatureF: 70.8,
                rainfallInches24h: 0.01,
                solarExposureMJ: 23.8,
                windSpeedMph: 9.6,
                windDirectionDegrees: 255
            ),
            insights: [
                insight(
                    "b5-i1",
                    "Low disease pressure",
                    "Dry canopy and good air movement keep fungal risk low. No spray action needed based on current readings.",
                    "low"
                )
            ]
        ),
        block(
            id: "b6",
            name: "Block 6",
            locationLabel: "Southwest canopy",
            risk: .moderate,
            center: coord(41.67745, -71.00130),
            polygon: quad(
                (41.67815, -71.00200),
                (41.67815, -71.00060),
                (41.67675, -71.00060),
                (41.67675, -71.00200)
            ),
            readings: VineyardCanopyReading(
                airTemperatureF: 74.6,
                relativeHumidityPct: 68,
                leafWetnessHours: 3.1,
                soilMoisturePct: 41,
                soilTemperatureF: 69.9,
                rainfallInches24h: 0.05,
                solarExposureMJ: 21.3,
                windSpeedMph: 6.0,
                windDirectionDegrees: 225
            ),
            insights: [
                insight(
                    "b6-i1",
                    "Irrigation timing note",
                    "Soil moisture is adequate. Avoid late-evening irrigation that could extend leaf wetness and raise mildew risk.",
                    "medium"
                )
            ]
        ),
        block(
            id: "b7",
            name: "Block 7",
            locationLabel: "West lower canopy",
            risk: .high,
            center: coord(41.67815, -71.00155),
            polygon: quad(
                (41.67885, -71.00225),
                (41.67885, -71.00085),
                (41.67745, -71.00085),
                (41.67745, -71.00225)
            ),
            readings: VineyardCanopyReading(
                airTemperatureF: 72.8,
                relativeHumidityPct: 84,
                leafWetnessHours: 4.9,
                soilMoisturePct: 47,
                soilTemperatureF: 68.1,
                rainfallInches24h: 0.11,
                solarExposureMJ: 16.9,
                windSpeedMph: 3.5,
                windDirectionDegrees: 90
            ),
            insights: [
                insight(
                    "b7-i1",
                    "Spray window recommendation",
                    "Apply fungicide when wind drops below 10 mph and before the next rain event. Current canopy RH supports infection.",
                    "high"
                ),
                insight(
                    "b7-i2",
                    "Harvest planning unaffected",
                    "Berry sugar accumulation is on track; disease risk is canopy-microclimate driven, not heat stress.",
                    "low"
                )
            ]
        ),
        block(
            id: "b8",
            name: "Block 8",
            locationLabel: "West upper canopy",
            risk: .low,
            center: coord(41.67955, -71.00155),
            polygon: quad(
                (41.68025, -71.00225),
                (41.68025, -71.00085),
                (41.67885, -71.00085),
                (41.67885, -71.00225)
            ),
            readings: VineyardCanopyReading(
                airTemperatureF: 74.9,
                relativeHumidityPct: 61,
                leafWetnessHours: 1.1,
                soilMoisturePct: 38,
                soilTemperatureF: 70.2,
                rainfallInches24h: 0.03,
                solarExposureMJ: 22.0,
                windSpeedMph: 7.8,
                windDirectionDegrees: 265
            ),
            insights: [
                insight(
                    "b8-i1",
                    "Stable microclimate",
                    "VPD and canopy humidity are in a comfortable range for vine health with minimal fungal pressure.",
                    "low"
                )
            ]
        ),
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

    // MARK: - Helpers

    private static func coord(_ lat: Double, _ lng: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func quad(
        _ nw: (Double, Double),
        _ ne: (Double, Double),
        _ se: (Double, Double),
        _ sw: (Double, Double)
    ) -> [CLLocationCoordinate2D] {
        [coord(nw.0, nw.1), coord(ne.0, ne.1), coord(se.0, se.1), coord(sw.0, sw.1)]
    }

    private static func insight(
        _ id: String,
        _ title: String,
        _ message: String,
        _ severity: String
    ) -> VineyardBlockInsight {
        VineyardBlockInsight(id: id, title: title, message: message, severity: severity)
    }

    private static func block(
        id: String,
        name: String,
        locationLabel: String,
        risk: VineyardRiskLevel,
        center: CLLocationCoordinate2D,
        polygon: [CLLocationCoordinate2D],
        readings: VineyardCanopyReading,
        insights: [VineyardBlockInsight]
    ) -> VineyardDemoBlock {
        VineyardDemoBlock(
            id: id,
            name: name,
            locationLabel: locationLabel,
            polygon: polygon,
            center: center,
            riskLevel: risk,
            readings: readings,
            insights: insights
        )
    }

    static var mapRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: mapCenter, span: mapSpan)
    }
}
