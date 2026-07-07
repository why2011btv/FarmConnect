import CoreLocation
import SwiftUI

enum VineyardRiskLevel: String, CaseIterable {
    case low
    case moderate
    case high

    var label: String {
        switch self {
        case .low: return "Low risk"
        case .moderate: return "Moderate risk"
        case .high: return "High risk"
        }
    }

    var fillColor: Color {
        switch self {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        }
    }

    var strokeColor: Color {
        switch self {
        case .low: return .green.opacity(0.9)
        case .moderate: return .orange.opacity(0.95)
        case .high: return .red.opacity(0.95)
        }
    }
}

struct VineyardCanopyReading {
    let airTemperatureF: Double
    let relativeHumidityPct: Double
    let leafWetnessHours: Double
    let soilMoisturePct: Double
    let soilTemperatureF: Double
    let rainfallInches24h: Double
    let solarExposureMJ: Double
    let windSpeedMph: Double
    let windDirectionDegrees: Double

    var windDirectionLabel: String {
        CompassDirection.label(for: windDirectionDegrees)
    }
}

struct VineyardBlockInsight: Identifiable {
    let id: String
    let title: String
    let message: String
    let severity: String
}

struct VineyardDemoBlock: Identifiable {
    let id: String
    let name: String
    let locationLabel: String
    let polygon: [CLLocationCoordinate2D]
    let center: CLLocationCoordinate2D
    let riskLevel: VineyardRiskLevel
    let readings: VineyardCanopyReading
    let grapeVariety: GrapeVariety
    let analytics: VineyardCanopyAnalyticsSummary
    let insights: [VineyardBlockInsight]
    /// Present when this block is backed by a live sensor node (within the last week).
    let liveSensor: BlockLiveSensorData?
    /// Set on demo blocks assigned to a physical sensor node (b1, b2).
    let sensorConnection: BlockSensorConnection?
    /// Whether each canopy metric came from a field sensor or weather API.
    let readingSources: CanopyReadingSources

    init(
        id: String,
        name: String,
        locationLabel: String,
        polygon: [CLLocationCoordinate2D],
        center: CLLocationCoordinate2D,
        riskLevel: VineyardRiskLevel,
        readings: VineyardCanopyReading,
        grapeVariety: GrapeVariety,
        analytics: VineyardCanopyAnalyticsSummary,
        insights: [VineyardBlockInsight],
        liveSensor: BlockLiveSensorData? = nil,
        sensorConnection: BlockSensorConnection? = nil,
        readingSources: CanopyReadingSources = CanopyReadingSources(all: .weather)
    ) {
        self.id = id
        self.name = name
        self.locationLabel = locationLabel
        self.polygon = polygon
        self.center = center
        self.riskLevel = riskLevel
        self.readings = readings
        self.grapeVariety = grapeVariety
        self.analytics = analytics
        self.insights = insights
        self.liveSensor = liveSensor
        self.sensorConnection = sensorConnection
        self.readingSources = readingSources
    }
}

enum CompassDirection {
    static func label(for degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalized + 22.5) / 45.0) % 8
        return directions[index]
    }
}

enum GeoPolygon {
    static func contains(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            let intersects = ((pi.latitude > point.latitude) != (pj.latitude > point.latitude))
                && (point.longitude < (pj.longitude - pi.longitude) * (point.latitude - pi.latitude)
                    / (pj.latitude - pi.latitude) + pi.longitude)
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }
}
