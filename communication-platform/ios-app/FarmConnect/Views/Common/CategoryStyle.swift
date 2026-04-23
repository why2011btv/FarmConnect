import SwiftUI

extension Category {
    /// Tinted background for a post card body.
    var cardBackground: Color {
        switch self {
        case .note:     return .gray.opacity(0.12)
        case .market:   return .green.opacity(0.14)
        case .disease:  return .red.opacity(0.12)
        case .pest:     return .yellow.opacity(0.18)
        case .weather:  return .blue.opacity(0.12)
        }
    }

    /// Outline color for a post card body.
    var cardBorder: Color {
        switch self {
        case .note:     return .gray.opacity(0.35)
        case .market:   return .green.opacity(0.35)
        case .disease:  return .red.opacity(0.35)
        case .pest:     return .yellow.opacity(0.45)
        case .weather:  return .blue.opacity(0.35)
        }
    }

    /// Background color for a small inline tag (capsule).
    var tagBackground: Color {
        switch self {
        case .note:     return .gray.opacity(0.22)
        case .market:   return .green.opacity(0.22)
        case .disease:  return .red.opacity(0.22)
        case .pest:     return .yellow.opacity(0.3)
        case .weather:  return .blue.opacity(0.22)
        }
    }

    /// Foreground color for the tag capsule text.
    var tagForeground: Color {
        switch self {
        case .note:     return .gray
        case .market:   return .green
        case .disease:  return .red
        case .pest:     return .orange
        case .weather:  return .blue
        }
    }
}
