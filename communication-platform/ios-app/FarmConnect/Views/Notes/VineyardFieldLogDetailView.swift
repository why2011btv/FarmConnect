import SwiftUI

struct VineyardFieldLogDetailView: View {
    let entry: VineyardFieldLogEntry
    var onDelete: (() -> Void)? = nil

    var body: some View {
        List {
            Section {
                Label(entry.kind.rawValue, systemImage: entry.kind.iconName)
                    .font(.headline)
                LabeledContent("Date", value: formattedDate(entry.createdAt))
            }

            Section("Location") {
                if let block = entry.blockChipLabel {
                    LabeledContent("Block", value: block)
                }
                LabeledContent("Rows / area", value: entry.locationDetail)
                if !entry.grapeVariety.isEmpty {
                    LabeledContent("Grape variety", value: entry.grapeVariety)
                }
            }

            if entry.kind == .spray {
                Section("Application") {
                    if let product = entry.product {
                        LabeledContent("Product", value: product)
                    }
                    if let rate = entry.applicationRate {
                        LabeledContent("Rate", value: rate)
                    }
                }
            }

            if entry.kind == .scouting {
                Section("Observation") {
                    if let issue = entry.issueType {
                        LabeledContent("Issue", value: issue)
                    }
                    if let severity = entry.severity {
                        LabeledContent("Severity", value: "\(severity) / 5")
                    }
                }
            }

            Section("Notes") {
                Text(entry.notes)
            }

            if entry.isBundledDemo {
                Section {
                    Text("Demo entry — illustrates structured spray and scouting records for presentations.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let onDelete {
                Section {
                    Button("Delete entry", role: .destructive, action: onDelete)
                }
            }
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
