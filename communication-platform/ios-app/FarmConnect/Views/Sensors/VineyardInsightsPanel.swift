import SwiftUI

struct VineyardInsightsPanel: View {
    let block: VineyardDemoBlock?
    let insights: [VineyardBlockInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(block == nil ? "Vineyard insights" : "Block insights")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            Divider()

            if insights.isEmpty {
                ContentUnavailableView(
                    "No insights",
                    systemImage: "lightbulb",
                    description: Text("Recommendations will appear here as sensors report.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(insights) { insight in
                            insightRow(insight)
                        }
                    }
                    .padding()
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }

    private func insightRow(_ insight: VineyardBlockInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(insight.severity.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(severityColor(insight.severity).opacity(0.2), in: Capsule())
                    .foregroundStyle(severityColor(insight.severity))
            }
            Text(insight.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .blue
        }
    }
}
