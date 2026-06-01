import Foundation

/// Bundled field-log entries for customer demos (no server required).
enum VineyardFieldLogDemoData {
    static let bundled: [VineyardFieldLogEntry] = [
        spray(
            id: "demo-spray-1",
            day: 28, month: 5,
            block: "b3", blockName: "Block 3",
            location: "North rows 12–18, lower terrace",
            variety: "Pinot Gris",
            product: "Sulfur (micronized)",
            rate: "6 lb/acre",
            notes: "Follow-up after high canopy humidity. Applied before forecast rain; REI 24 h."
        ),
        scouting(
            id: "demo-scout-1",
            day: 29, month: 5,
            block: "b3", blockName: "Block 3",
            location: "North rows 12–18",
            variety: "Pinot Gris",
            issue: .powderyMildew,
            severity: 4,
            notes: "White powder on upper leaf surfaces, ~15% of canopy in flagged rows. Matches sensor high-risk band."
        ),
        spray(
            id: "demo-spray-2",
            day: 2, month: 6,
            block: "b4", blockName: "Block 4",
            location: "Middle section, west half",
            variety: "Merlot",
            product: "Stylet-Oil",
            rate: "1.5 qt/acre",
            notes: "Moderate mildew pressure; oil for suppression between sulfur intervals."
        ),
        scouting(
            id: "demo-scout-2",
            day: 4, month: 6,
            block: "b6", blockName: "Block 6",
            location: "South rows, upper third",
            variety: "Cabernet Franc",
            issue: .downyMildew,
            severity: 3,
            notes: "Oil spots on lower leaves after humid nights. No spread to clusters yet."
        ),
        spray(
            id: "demo-spray-3",
            day: 6, month: 6,
            block: "b1", blockName: "Block 1",
            location: "Rows 4–8, east side (Cab Franc section)",
            variety: "Cabernet Franc",
            product: "Sulfur (micronized)",
            rate: "5 lb/acre",
            notes: "Preventive pass; block remains low risk on canopy map."
        ),
        scouting(
            id: "demo-scout-3",
            day: 8, month: 6,
            block: "b7", blockName: "Block 7",
            location: "South rows, full pass",
            variety: "Pinot Gris",
            issue: .other,
            severity: 1,
            notes: "Routine walk-through. Canopy dry, no mildew signs. Noted minor bird netting gap at row 22."
        ),
        spray(
            id: "demo-spray-4",
            day: 10, month: 6,
            block: "b5", blockName: "Block 5",
            location: "Middle section, east — Chardonnay rows 1–12",
            variety: "Chardonnay",
            product: "Horticultural oil",
            rate: "1 qt/acre",
            notes: "Low-risk block; oil for mite prevention ahead of bloom set."
        ),
        scouting(
            id: "demo-scout-4",
            day: 11, month: 6,
            block: "b2", blockName: "Block 2",
            location: "North rows 6–10",
            variety: "Merlot",
            issue: .leafhopper,
            severity: 2,
            notes: "Adults on leaf undersides, below economic threshold. Recheck in 5 days."
        ),
        scouting(
            id: "demo-scout-5",
            day: 12, month: 6,
            block: "b8", blockName: "Block 8",
            location: "South rows, lower",
            variety: "Riesling",
            issue: .nutrient,
            severity: 2,
            notes: "Interveinal yellowing on young leaves — possible N deficiency on sandy strip. Soil sample planned."
        ),
        spray(
            id: "demo-spray-5",
            day: 13, month: 6,
            block: "b3", blockName: "Block 3",
            location: "North rows 12–18 (spot treatment)",
            variety: "Pinot Gris",
            product: "Rally 40WSP",
            rate: "5 oz/acre",
            notes: "Targeted on scouting flags only. Wind 6 mph SW; 48 h before rain window per outlook."
        ),
    ]

    // MARK: - Builders

    private static func demoDate(year: Int = 2026, month: Int, day: Int, hour: Int = 10) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func spray(
        id: String,
        day: Int,
        month: Int,
        block: String,
        blockName: String,
        location: String,
        variety: String,
        product: String,
        rate: String,
        notes: String
    ) -> VineyardFieldLogEntry {
        VineyardFieldLogEntry(
            id: id,
            kind: .spray,
            createdAt: demoDate(month: month, day: day),
            blockId: block,
            blockName: blockName,
            locationDetail: location,
            grapeVariety: variety,
            title: "\(product) — \(blockName)",
            notes: notes,
            product: product,
            applicationRate: rate,
            issueType: nil,
            severity: nil
        )
    }

    private static func scouting(
        id: String,
        day: Int,
        month: Int,
        block: String,
        blockName: String,
        location: String,
        variety: String,
        issue: VineyardScoutingIssue,
        severity: Int,
        notes: String
    ) -> VineyardFieldLogEntry {
        VineyardFieldLogEntry(
            id: id,
            kind: .scouting,
            createdAt: demoDate(month: month, day: day, hour: 16),
            blockId: block,
            blockName: blockName,
            locationDetail: location,
            grapeVariety: variety,
            title: "\(issue.rawValue) — \(blockName)",
            notes: notes,
            product: nil,
            applicationRate: nil,
            issueType: issue.rawValue,
            severity: severity
        )
    }
}
