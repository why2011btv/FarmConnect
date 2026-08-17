import Foundation

/// Client-side handling of farm access codes.
///
/// Must agree with `normalizeAccessCode` in the backend's `src/lib/accessCode.ts`: whatever this
/// produces is what gets sent to `/v1/farms/claim`, so a disagreement here turns a valid printed
/// code into one that never works.
enum AccessCodeFormatter {
    /// Characters the server treats as typos for an alphabet character.
    private static let lookalikes: [Character: Character] = ["I": "1", "L": "1", "O": "0", "U": "V"]

    static let bodyLength = 16
    static let displayPrefix = "PB"
    private static let groupSize = 4

    /// The canonical 16-character body, with the display prefix, dashes and look-alikes resolved.
    ///
    /// The generator never mints a body that itself begins with "PB", which is what makes stripping
    /// the prefix unconditionally safe while the user is still typing.
    static func canonicalBody(_ raw: String) -> String {
        var body = String(
            raw.uppercased()
                .filter { $0.isLetter || $0.isNumber }
                .map { lookalikes[$0] ?? $0 }
        )
        if body.hasPrefix(displayPrefix) { body.removeFirst(displayPrefix.count) }
        return String(body.prefix(bodyLength))
    }

    static func isComplete(_ raw: String) -> Bool {
        canonicalBody(raw).count == bodyLength
    }

    /// Regroups input into `XXXX-XXXX-XXXX-XXXX` as the user types, so a code read off a card
    /// matches however they space it.
    ///
    /// Deliberately does **not** prepend `PB-`. The UI renders the prefix as a fixed label beside
    /// the field instead: injecting it into editable text makes the first characters ambiguous —
    /// a lone "P" would become "PB-P", and the user's own "B" would then land in the body.
    static func formatBody(_ raw: String) -> String {
        let body = canonicalBody(raw)
        if body.isEmpty { return "" }

        var groups: [String] = []
        var index = body.startIndex
        while index < body.endIndex {
            let end = body.index(index, offsetBy: groupSize, limitedBy: body.endIndex) ?? body.endIndex
            groups.append(String(body[index..<end]))
            index = end
        }
        return groups.joined(separator: "-")
    }

    /// Full printable form, for displaying a complete code.
    static func displayCode(_ raw: String) -> String {
        "\(displayPrefix)-\(formatBody(raw))"
    }
}
