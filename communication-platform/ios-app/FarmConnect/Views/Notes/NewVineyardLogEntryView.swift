import SwiftUI

struct NewVineyardLogEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = VineyardFieldLogStore.shared

    @State private var kind: VineyardLogKind = .spray
    @State private var blockOption: VineyardBlockOption = .none
    @State private var locationDetail = ""
    @State private var grapeVariety: GrapeVariety = .notSpecified
    @State private var notes = ""
    @State private var product = ""
    @State private var applicationRate = ""
    @State private var issue: VineyardScoutingIssue = .powderyMildew
    @State private var severity = 3

    private let sprayProducts = [
        "Sulfur (micronized)",
        "Stylet-Oil",
        "Horticultural oil",
        "Rally 40WSP",
        "Luna Experience",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Record type", selection: $kind) {
                        Text("Spray").tag(VineyardLogKind.spray)
                        Text("Scouting").tag(VineyardLogKind.scouting)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Where") {
                    Picker("Block (map)", selection: $blockOption) {
                        ForEach(VineyardBlockOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    TextField("Rows / area (free text)", text: $locationDetail, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Grape variety", selection: $grapeVariety) {
                        ForEach(GrapeVariety.allCases.filter { $0 != .notSpecified }) { variety in
                            Text(variety.displayName).tag(variety)
                        }
                        Text("Not specified").tag(GrapeVariety.notSpecified)
                    }
                }

                if kind == .spray {
                    Section("Application") {
                        Picker("Product", selection: $product) {
                            Text("Select…").tag("")
                            ForEach(sprayProducts, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        TextField("Rate (e.g. 6 lb/acre)", text: $applicationRate)
                    }
                } else {
                    Section("Observation") {
                        Picker("Issue", selection: $issue) {
                            ForEach(VineyardScoutingIssue.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        Picker("Severity", selection: $severity) {
                            ForEach(1...5, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Details", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(kind == .spray ? "Log spray" : "Log scouting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !locationDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (kind == .scouting || !product.isEmpty)
    }

    private func save() {
        let blockName = blockOption == .none ? nil : blockOption.displayName
        let varietyLabel = grapeVariety == .notSpecified ? "" : grapeVariety.displayName
        let trimmedLocation = locationDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let title: String
        let entry: VineyardFieldLogEntry

        switch kind {
        case .spray:
            let productName = product.isEmpty ? "Spray" : product
            title = blockName.map { "\(productName) — \($0)" } ?? productName
            entry = VineyardFieldLogEntry(
                id: "user-\(UUID().uuidString)",
                kind: .spray,
                createdAt: Date(),
                blockId: blockOption.blockId,
                blockName: blockName,
                locationDetail: trimmedLocation,
                grapeVariety: varietyLabel,
                title: title,
                notes: trimmedNotes.isEmpty ? "Logged from field." : trimmedNotes,
                product: productName,
                applicationRate: applicationRate.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                issueType: nil,
                severity: nil
            )
        case .scouting:
            title = blockName.map { "\(issue.rawValue) — \($0)" } ?? issue.rawValue
            entry = VineyardFieldLogEntry(
                id: "user-\(UUID().uuidString)",
                kind: .scouting,
                createdAt: Date(),
                blockId: blockOption.blockId,
                blockName: blockName,
                locationDetail: trimmedLocation,
                grapeVariety: varietyLabel,
                title: title,
                notes: trimmedNotes.isEmpty ? "Scouting observation." : trimmedNotes,
                product: nil,
                applicationRate: nil,
                issueType: issue.rawValue,
                severity: severity
            )
        case .general:
            title = "Field note"
            entry = VineyardFieldLogEntry(
                id: "user-\(UUID().uuidString)",
                kind: .general,
                createdAt: Date(),
                blockId: blockOption.blockId,
                blockName: blockName,
                locationDetail: trimmedLocation,
                grapeVariety: varietyLabel,
                title: title,
                notes: trimmedNotes,
                product: nil,
                applicationRate: nil,
                issueType: nil,
                severity: nil
            )
        }

        store.add(entry)
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
