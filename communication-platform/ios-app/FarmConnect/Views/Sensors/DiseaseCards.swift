import SwiftUI

func diseaseLevelColor(_ level: String) -> Color {
    switch level {
    case "high": return .red
    case "moderate": return .orange
    case "low": return .green
    default: return .secondary
    }
}

func diseaseLevelLabel(_ level: String) -> String {
    switch level {
    case "high": return "HIGH"
    case "moderate": return "MODERATE"
    case "low": return "LOW"
    default: return "N/A"
    }
}

func diseaseActionIcon(_ category: String) -> String {
    switch category {
    case "scout": return "magnifyingglass"
    case "cultural": return "leaf"
    case "protect": return "shield.lefthalf.filled"
    default: return "circle"
    }
}

func diseaseActionColor(_ category: String) -> Color {
    switch category {
    case "scout": return .blue
    case "cultural": return .green
    case "protect": return .orange
    default: return .secondary
    }
}

/// One disease's card: level, what's happening (why), and the tiered actions (each with its reason).
/// Shared by the vineyard-wide disease view and the per-block view in the block detail.
struct DiseaseCard: View {
    let disease: DiseaseRisk

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(disease.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(diseaseLevelLabel(disease.level))
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(diseaseLevelColor(disease.level).opacity(0.2), in: Capsule())
                    .foregroundStyle(diseaseLevelColor(disease.level))
            }
            Text(disease.headline).font(.footnote.weight(.medium))
            Text(disease.detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actions = disease.actions, !actions.isEmpty {
                Divider().padding(.vertical, 2)
                Text("What to do").font(.caption.weight(.semibold))
                ForEach(actions) { act in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: diseaseActionIcon(act.category))
                            .font(.caption)
                            .foregroundStyle(diseaseActionColor(act.category))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(act.action).font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(act.reason).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
