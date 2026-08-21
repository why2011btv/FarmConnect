import SwiftUI

/// What a customer sees before they have drawn their vineyard.
///
/// Redeeming an access code should be enough to see your data, so this shows node status,
/// readings and insights as a plain list, with drawing the map offered as an enhancement rather
/// than a prerequisite. Previously this screen was an empty map telling you to go and configure
/// something, which put a setup wall between a paying grower and the sensors they just installed.
struct SensorNodeListView: View {
    let devices: [SensorDeviceOverview]
    let insights: [SensorInsight]
    let isLoading: Bool
    let onSetUpVineyard: () -> Void

    private func isOnline(_ d: SensorDeviceOverview) -> Bool {
        d.status.lowercased() == "online"
    }

    private func lastSeen(_ d: SensorDeviceOverview) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(d.lastSeenAt) / 1000)
        // A node provisioned but never heard from carries a zero timestamp.
        guard d.lastSeenAt > 0 else { return "never reported" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func formatted(_ r: SensorReading) -> String {
        let label = r.sensorType.replacingOccurrences(of: "_", with: " ").capitalized
        return "\(label) \(String(format: "%.1f", r.value))\(r.unit == "%" ? "%" : " \(r.unit)")"
    }

    private func severityColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        List {
            if devices.isEmpty && !isLoading {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No readings yet").font(.headline)
                        Text("Your nodes will appear here as soon as they power on and report. "
                             + "Nothing to configure in the app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !insights.isEmpty {
                Section("Insights") {
                    ForEach(insights) { insight in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(severityColor(insight.severity))
                                    .frame(width: 8, height: 8)
                                Text(insight.title).font(.headline)
                            }
                            Text(insight.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !devices.isEmpty {
                Section("Nodes") {
                    ForEach(devices) { device in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(isOnline(device) ? Color.green : Color.secondary)
                                    .frame(width: 8, height: 8)
                                Text(device.name).font(.headline)
                                Spacer()
                                Text(lastSeen(device))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !device.locationLabel.isEmpty {
                                Text(device.locationLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !device.readings.isEmpty {
                                Text(device.readings.map(formatted).joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Button(action: onSetUpVineyard) {
                    Label("Set up your vineyard map", systemImage: "map")
                }
            } footer: {
                Text("Optional. Drawing your blocks adds the map view and per-block risk, and "
                     + "attaches each node to the block it sits in.")
            }
        }
    }
}
