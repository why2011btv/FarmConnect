import Foundation

/// Demo vineyard field log — spray applications and scouting observations.
enum VineyardLogKind: String, Codable, CaseIterable, Identifiable {
    case spray = "Spray"
    case scouting = "Scouting"
    case general = "General"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .spray: return "drop.triangle.fill"
        case .scouting: return "leaf.fill"
        case .general: return "note.text"
        }
    }

    var tintName: String {
        switch self {
        case .spray: return "blue"
        case .scouting: return "orange"
        case .general: return "gray"
        }
    }
}

struct VineyardFieldLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let kind: VineyardLogKind
    let createdAt: Date
    /// Demo block id (b1…b8) when tied to the canopy map.
    let blockId: String?
    let blockName: String?
    /// Row-level or in-block detail, e.g. "Rows 4–8, east side".
    let locationDetail: String
    let grapeVariety: String
    let title: String
    let notes: String
    let product: String?
    let applicationRate: String?
    let issueType: String?
    let severity: Int?

    var isBundledDemo: Bool { id.hasPrefix("demo-") }

    var createdAtMs: Int64 {
        Int64(createdAt.timeIntervalSince1970 * 1000)
    }

    var summaryLine: String {
        switch kind {
        case .spray:
            let productLabel = product ?? "Spray"
            return "\(productLabel) · \(locationDetail)"
        case .scouting:
            let issue = issueType ?? "Observation"
            return "\(issue) · \(locationDetail)"
        case .general:
            return locationDetail.isEmpty ? notes : locationDetail
        }
    }

    var blockChipLabel: String? {
        if let blockName, !blockName.isEmpty { return blockName }
        return nil
    }
}

enum VineyardBlockOption: String, CaseIterable, Identifiable {
    case none = ""
    case b1 = "b1"
    case b2 = "b2"
    case b3 = "b3"
    case b4 = "b4"
    case b5 = "b5"
    case b6 = "b6"
    case b7 = "b7"
    case b8 = "b8"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No block"
        case .b1: return "Block 1"
        case .b2: return "Block 2"
        case .b3: return "Block 3"
        case .b4: return "Block 4"
        case .b5: return "Block 5"
        case .b6: return "Block 6"
        case .b7: return "Block 7"
        case .b8: return "Block 8"
        }
    }

    var blockId: String? {
        rawValue.isEmpty ? nil : rawValue
    }
}

enum VineyardScoutingIssue: String, CaseIterable, Identifiable {
    case powderyMildew = "Powdery mildew"
    case downyMildew = "Downy mildew"
    case botrytis = "Botrytis"
    case leafhopper = "Leafhopper"
    case nutrient = "Nutrient deficiency"
    case other = "Other"

    var id: String { rawValue }
}
