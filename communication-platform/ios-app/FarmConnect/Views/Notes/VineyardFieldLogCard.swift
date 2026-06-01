import SwiftUI

struct VineyardFieldLogCard: View {
    let entry: VineyardFieldLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.kind.iconName)
                    .font(.title3)
                    .foregroundStyle(kindColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(entry.summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            FlowLayoutTags(tags: chipLabels)

            Text(entry.notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(relativeDate(entry.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var kindColor: Color {
        switch entry.kind {
        case .spray: return .blue
        case .scouting: return .orange
        case .general: return .secondary
        }
    }

    private var chipLabels: [String] {
        var tags: [String] = []
        if let block = entry.blockChipLabel { tags.append(block) }
        if !entry.grapeVariety.isEmpty { tags.append(entry.grapeVariety) }
        if entry.kind == .spray, let rate = entry.applicationRate, !rate.isEmpty {
            tags.append(rate)
        }
        if entry.kind == .scouting, let issue = entry.issueType {
            tags.append(issue)
        }
        if let severity = entry.severity {
            tags.append("Severity \(severity)/5")
        }
        return tags
    }

    private func relativeDate(_ date: Date) -> String {
        TimeFormatting.relative(from: Int64(date.timeIntervalSince1970 * 1000))
    }
}

/// Simple horizontal chip row.
private struct FlowLayoutTags: View {
    let tags: [String]

    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }
}
