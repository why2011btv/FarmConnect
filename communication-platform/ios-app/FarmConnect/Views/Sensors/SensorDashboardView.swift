import SwiftUI

struct SensorDashboardView: View {
    enum SensorPanel: String, CaseIterable, Identifiable {
        case insights = "Insights"
        case devices = "Devices"

        var id: String { rawValue }
    }

    @EnvironmentObject private var sensorViewModel: SensorViewModel
    @State private var selectedPanel: SensorPanel = .insights
    @State private var pendingInsightToDismiss: SensorInsight?
    @State private var showDismissConfirmation = false

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

                if let error = sensorViewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ZStack {
                    if selectedPanel == .insights {
                        insightsList
                    } else {
                        devicesList
                    }

                    if sensorViewModel.isLoading && sensorViewModel.devices.isEmpty {
                        ProgressView("Loading sensors...")
                    }
                }
            }
            .navigationTitle("Sensors")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenuButton()
                }
            }
            .task {
                await sensorViewModel.load()
            }
            .confirmationDialog(
                "Dismiss insight?",
                isPresented: $showDismissConfirmation,
                titleVisibility: .visible,
                presenting: pendingInsightToDismiss
            ) { insight in
                Button("Dismiss", role: .destructive) {
                    sensorViewModel.dismissInsight(id: insight.id)
                    pendingInsightToDismiss = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingInsightToDismiss = nil
                }
            } message: { insight in
                Text("Hide \"\(insight.title)\" from Insights?")
            }
        }
    }

    private var insightsList: some View {
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingInsightToDismiss = insight
                        showDismissConfirmation = true
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await sensorViewModel.load() }
        .overlay {
            if sensorViewModel.insights.isEmpty && !sensorViewModel.isLoading {
                ContentUnavailableView("No insights yet", systemImage: "sparkles")
            }
        }
    }

    private var devicesList: some View {
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
        .refreshable { await sensorViewModel.load() }
        .overlay {
            if sensorViewModel.devices.isEmpty && !sensorViewModel.isLoading {
                ContentUnavailableView("No sensor devices", systemImage: "waveform.path.ecg")
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
