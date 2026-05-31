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
            name: "South Block",
            locationLabel: "South vertical rows",
            risk: .low,
            center: coord(41.67750, -71.00030),
            polygon: quad(
                (41.67910, -71.00075), // NW
                (41.67910, -70.99975), // NE
                (41.67600, -70.99960), // SE
                (41.67600, -71.00065)  // SW
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
            name: "Middle Block",
            locationLabel: "Main trapezoid section",
            risk: .moderate,
            center: coord(41.68060, -71.00080),
            polygon: quad(
                (41.68210, -71.00160), // NW
                (41.68205, -70.99980), // NE
                (41.67910, -70.99975), // SE
                (41.67910, -71.00075)  // SW
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
            name: "North Block",
            locationLabel: "Upper horizontal rows",
            risk: .high,
            center: coord(41.68245, -71.00080),
            polygon: quad(
                (41.68270, -71.00195), // NW
                (41.68260, -70.99970), // NE
                (41.68205, -70.99980), // SE
                (41.68210, -71.00160)  // SW
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
    ]

    static let generalInsights: [VineyardBlockInsight] = [
        insight(
            "g1",
            "Vineyard-wide disease outlook",
            "1 of 3 canopy blocks shows elevated powdery or downy mildew risk based on humidity, leaf wetness, and airflow. Focus scouting on the North Block.",
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
            "Recent light rainfall and calm overnight winds increased canopy moisture in the northern rows. The South Block with good air drainage remains in the low-risk zone.",
            "low"
        ),
        insight(
            "g4",
            "Sensor network status",
            "All 3 canopy nodes are reporting. Tap a block on the map to view block-level microclimate readings and tailored recommendations.",
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
