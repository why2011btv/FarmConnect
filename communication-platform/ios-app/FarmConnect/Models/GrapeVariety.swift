import Foundation

/// Common vinifera varieties for New England / demo blocks.
enum GrapeVariety: String, CaseIterable, Identifiable, Codable {
    case notSpecified = ""
    case cabernetFranc = "Cabernet Franc"
    case merlot = "Merlot"
    case pinotGris = "Pinot Gris"
    case chardonnay = "Chardonnay"
    case riesling = "Riesling"
    case pinotNoir = "Pinot Noir"
    case sauvignonBlanc = "Sauvignon Blanc"
    case vidal = "Vidal Blanc"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notSpecified: return "Not specified"
        default: return rawValue
        }
    }

    /// Relative susceptibility notes for demo / future AI context (0–1 scale).
    var powderySusceptibility: Double {
        switch self {
        case .pinotGris, .riesling: return 0.85
        case .merlot, .chardonnay: return 0.7
        case .cabernetFranc, .pinotNoir: return 0.6
        case .sauvignonBlanc, .vidal: return 0.55
        case .other: return 0.65
        case .notSpecified: return 0.65
        }
    }

    var downySusceptibility: Double {
        switch self {
        case .riesling, .merlot: return 0.85
        case .pinotGris, .chardonnay: return 0.7
        case .cabernetFranc, .pinotNoir: return 0.65
        case .sauvignonBlanc, .vidal: return 0.6
        case .other: return 0.7
        case .notSpecified: return 0.7
        }
    }
}

struct VineyardBlockSettings: Codable, Equatable {
    var grapeVariety: String

    static let empty = VineyardBlockSettings(grapeVariety: "")

    var variety: GrapeVariety {
        GrapeVariety(rawValue: grapeVariety) ?? .notSpecified
    }
}
