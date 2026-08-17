import SwiftUI

/// Shows secrets that exist only in this moment.
///
/// Access codes and node ingest keys are stored as hashes, so nothing here can be retrieved again.
/// The screen is deliberately hard to dismiss by accident: it requires an explicit acknowledgement
/// rather than a swipe, and offers copy/share so the values can be saved somewhere durable.
struct AdminSecretsView: View {
    let farmName: String
    let accessCode: String?
    let nodes: [AdminProvisionedNode]

    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false

    private var shareText: String {
        var lines = ["Persephone's Basket — \(farmName)"]
        if let accessCode {
            lines.append("")
            lines.append("Access code (print on the card in the box):")
            lines.append(accessCode)
        }
        if !nodes.isEmpty {
            lines.append("")
            lines.append("Per-node ingest keys:")
            for node in nodes {
                lines.append("\(node.name)  deviceId=\(node.id)")
                lines.append("  x-device-key=\(node.ingestKey)")
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        "These are shown once. They are stored only as hashes and cannot be recovered — save them now.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.footnote)
                }

                if let accessCode {
                    Section("Access code") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(accessCode)
                                .font(.system(.title3, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Print this on the card that ships in the box. Anyone on the crew can redeem it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            UIPasteboard.general.string = accessCode
                        } label: {
                            Label("Copy access code", systemImage: "doc.on.doc")
                        }
                    }
                }

                if !nodes.isEmpty {
                    Section("Node ingest keys") {
                        ForEach(nodes) { node in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.name).font(.headline)
                                Text("deviceId = \(node.id)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text("x-device-key = \(node.ingestKey)")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    ShareLink(item: shareText) {
                        Label("Share everything", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = shareText
                    } label: {
                        Label("Copy everything", systemImage: "doc.on.doc.fill")
                    }
                }

                Section {
                    Toggle("I've saved these somewhere safe", isOn: $acknowledged)
                    Button("Done") { dismiss() }
                        .disabled(!acknowledged)
                }
            }
            .navigationTitle(farmName)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!acknowledged)
        }
    }
}
