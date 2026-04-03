import SwiftUI

struct SensorDashboardView: View {
    enum SensorPanel: String, CaseIterable, Identifiable {
        case insights = "Insights"
        case devices = "Devices"

        var id: String { rawValue }
    }

    @EnvironmentObject private var sensorViewModel: SensorViewModel
    @State private var selectedPanel: SensorPanel = .insights

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("Sensor panel", selection: $selectedPanel) {
                    ForEach(SensorPanel.allCases) { panel in
                        Text(panel.rawValue).tag(panel)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if sensorViewModel.isLoading {
                    ProgressView("Loading sensors...")
                        .frame(maxHeight: .infinity)
                } else if let error = sensorViewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxHeight: .infinity)
                } else if sensorViewModel.devices.isEmpty {
                    ContentUnavailableView("No sensor devices", systemImage: "waveform.path.ecg")
                        .frame(maxHeight: .infinity)
                } else {
                    if selectedPanel == .insights {
                        if sensorViewModel.insights.isEmpty {
                            ContentUnavailableView("No insights yet", systemImage: "sparkles")
                                .frame(maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(sensorViewModel.insights) { insight in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(insight.title)
                                                .font(.headline)
                                            Spacer()
                                            Text(insight.severity.uppercased())
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(severityColor(insight.severity).opacity(0.2), in: Capsule())
                                        }
                                        Text(insight.message)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                            .listStyle(.insetGrouped)
                        }
                    } else {
                        List {
                            ForEach(sensorViewModel.devices) { device in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(device.name)
                                            .font(.headline)
                                        Spacer()
                                        Text(device.status.uppercased())
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                (device.status == "online" ? Color.green.opacity(0.2) : Color.red.opacity(0.2)),
                                                in: Capsule()
                                            )
                                    }
                                    Text("\(device.farmName) · \(device.locationLabel)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    ForEach(device.readings, id: \.sensorType) { reading in
                                        HStack {
                                            Text(readableLabel(reading.sensorType))
                                            Spacer()
                                            Text("\(reading.value, specifier: "%.1f") \(reading.unit)")
                                                .bold()
                                        }
                                        .font(.footnote)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Sensors")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task { await sensorViewModel.load() }
                    }
                }
            }
            .task {
                await sensorViewModel.load()
            }
        }
    }

    private func readableLabel(_ sensorType: String) -> String {
        switch sensorType {
        case "temperature":
            return "Temperature"
        case "humidity":
            return "Humidity"
        case "soil_moisture":
            return "Soil moisture"
        default:
            return sensorType.replacingOccurrences(of: "_", with: " ").capitalized
        }
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
