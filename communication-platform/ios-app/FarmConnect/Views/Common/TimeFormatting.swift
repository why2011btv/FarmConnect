import Foundation

enum TimeFormatting {
    /// Abbreviated relative time, e.g. "3m ago", "2h ago", "Yesterday".
    static func relative(from timestampMs: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Short time-of-day for today's timestamps, or medium date style otherwise.
    static func listPreview(from date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let interval = now.timeIntervalSince(date)
        if interval < 7 * 24 * 3600 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    /// Short time-of-day for today's timestamps, or medium date style otherwise.
    static func listPreview(from timestampMs: Int64, now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        return listPreview(from: date, now: now)
    }
}
