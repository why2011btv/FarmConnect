import CoreLocation
import Foundation
import MapKit

/// Bundled demo vineyard data (Bristol County, MA coordinates). Generic labels in UI.
enum VineyardDemoData {
    static let mapCenter = CLLocationCoordinate2D(latitude: 41.67914, longitude: -70.999375)
    static let mapSpan = MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.014)

    /// Default rectangles: north = 3 horizontal strips, middle = 2 columns, south = 3 vertical strips.
    static let defaultRectangles: [VineyardBlockRectangle] = [
        rect("b1", 41.68262, -71.00085, halfLat: 0.00007, halfLng: 0.00042),
        rect("b2", 41.68242, -71.00085, halfLat: 0.00007, halfLng: 0.00042),
        rect("b3", 41.68222, -71.00085, halfLat: 0.00007, halfLng: 0.00042),
        rect("b4", 41.68105, -71.00115, halfLat: 0.00038, halfLng: 0.00020, rotation: -14),
        rect("b5", 41.68105, -71.00045, halfLat: 0.00038, halfLng: 0.00020, rotation: -14),
        rect("b6", 41.67955, -71.00085, halfLat: 0.00022, halfLng: 0.00016, rotation: -14),
        rect("b7", 41.67875, -71.00085, halfLat: 0.00022, halfLng: 0.00016, rotation: -14),
        rect("b8", 41.67795, -71.00085, halfLat: 0.00022, halfLng: 0.00016, rotation: -14),
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

    static func makeBlocks(rectangles: [VineyardBlockRectangle]) -> [VineyardDemoBlock] {
        rectangles.compactMap { rectangle in
            guard let template = blockTemplates[rectangle.id] else { return nil }
            return VineyardDemoBlock(
                id: rectangle.id,
                name: template.name,
                locationLabel: template.locationLabel,
                polygon: rectangle.polygon,
                center: rectangle.center,
                riskLevel: template.risk,
                readings: template.readings,
                insights: template.insights
            )
        }
    }

    static var mapRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: mapCenter, span: mapSpan)
    }

    // MARK: - Block metadata (readings / risk do not depend on map position)

    private struct BlockTemplate {
        let name: String
        let locationLabel: String
        let risk: VineyardRiskLevel
        let readings: VineyardCanopyReading
        let insights: [VineyardBlockInsight]
    }

    private static let blockTemplates: [String: BlockTemplate] = [
        "b1": template(
            name: "Block 1",
            locationLabel: "North rows (upper)",
            risk: .low,
            readings: readings(
                temp: 74.2, rh: 58, leafWet: 0.6, soilMoist: 39, soilTemp: 69.5,
                rain: 0.02, solar: 22.4, wind: 8.2, windDir: 240
            ),
            insights: [insight("b1-i1", "Canopy conditions favorable", "Humidity and leaf wetness are below thresholds for powdery and downy mildew development.", "low")]
        ),
        "b2": template(
            name: "Block 2",
            locationLabel: "North rows (middle)",
            risk: .moderate,
            readings: readings(
                temp: 73.8, rh: 72, leafWet: 2.8, soilMoist: 44, soilTemp: 68.8,
                rain: 0.08, solar: 20.1, wind: 5.4, windDir: 210
            ),
            insights: [insight("b2-i1", "Monitor overnight humidity", "Extended leaf wetness after dew may elevate downy mildew risk if RH stays above 75% tonight.", "medium")]
        ),
        "b3": template(
            name: "Block 3",
            locationLabel: "North rows (lower)",
            risk: .high,
            readings: readings(
                temp: 72.4, rh: 88, leafWet: 6.2, soilMoist: 48, soilTemp: 67.9,
                rain: 0.14, solar: 17.6, wind: 2.8, windDir: 55
            ),
            insights: [
                insight("b3-i1", "Elevated downy mildew risk", "High RH, recent rain, and low airflow in the canopy favor downy mildew. Consider a protectant spray within 48 hours.", "high"),
                insight("b3-i2", "Leaf wetness accumulation", "Canopy sensors logged over 6 hours of leaf wetness in the last 24 hours.", "high"),
            ]
        ),
        "b4": template(
            name: "Block 4",
            locationLabel: "Middle section (west)",
            risk: .high,
            readings: readings(
                temp: 71.9, rh: 86, leafWet: 5.4, soilMoist: 46, soilTemp: 67.2,
                rain: 0.12, solar: 18.2, wind: 3.1, windDir: 70
            ),
            insights: [insight("b4-i1", "Powdery mildew pressure building", "Warm canopy temperatures with sustained humidity support powdery mildew. Scout undersides of leaves.", "high")]
        ),
        "b5": template(
            name: "Block 5",
            locationLabel: "Middle section (east)",
            risk: .low,
            readings: readings(
                temp: 75.1, rh: 55, leafWet: 0.4, soilMoist: 36, soilTemp: 70.8,
                rain: 0.01, solar: 23.8, wind: 9.6, windDir: 255
            ),
            insights: [insight("b5-i1", "Low disease pressure", "Dry canopy and good air movement keep fungal risk low.", "low")]
        ),
        "b6": template(
            name: "Block 6",
            locationLabel: "South rows (upper)",
            risk: .moderate,
            readings: readings(
                temp: 74.6, rh: 68, leafWet: 3.1, soilMoist: 41, soilTemp: 69.9,
                rain: 0.05, solar: 21.3, wind: 6.0, windDir: 225
            ),
            insights: [insight("b6-i1", "Irrigation timing note", "Avoid late-evening irrigation that could extend leaf wetness and raise mildew risk.", "medium")]
        ),
        "b7": template(
            name: "Block 7",
            locationLabel: "South rows (middle)",
            risk: .high,
            readings: readings(
                temp: 72.8, rh: 84, leafWet: 4.9, soilMoist: 47, soilTemp: 68.1,
                rain: 0.11, solar: 16.9, wind: 3.5, windDir: 90
            ),
            insights: [
                insight("b7-i1", "Spray window recommendation", "Apply fungicide when wind drops below 10 mph and before the next rain event.", "high"),
                insight("b7-i2", "Harvest planning unaffected", "Berry sugar accumulation is on track; disease risk is canopy-microclimate driven.", "low"),
            ]
        ),
        "b8": template(
            name: "Block 8",
            locationLabel: "South rows (lower)",
            risk: .low,
            readings: readings(
                temp: 74.9, rh: 61, leafWet: 1.1, soilMoist: 38, soilTemp: 70.2,
                rain: 0.03, solar: 22.0, wind: 7.8, windDir: 265
            ),
            insights: [insight("b8-i1", "Stable microclimate", "VPD and canopy humidity are in a comfortable range with minimal fungal pressure.", "low")]
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
        risk: VineyardRiskLevel,
        readings: VineyardCanopyReading,
        insights: [VineyardBlockInsight]
    ) -> BlockTemplate {
        BlockTemplate(name: name, locationLabel: locationLabel, risk: risk, readings: readings, insights: insights)
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
