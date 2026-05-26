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
            .navigationTitle("Vineyard Sensors")
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
            Section {
                vineyardSnapshotCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            } header: {
                Text("Vineyard Snapshot")
            } footer: {
                Text("Quick estimates from your latest sensor readings. GDD uses a 50°F base.")
                    .font(.caption2)
            }

            Section("Insights") {
                if sensorViewModel.insights.isEmpty && !sensorViewModel.isLoading {
                    Text("No insights yet. We'll surface alerts here as your vineyard sensors report.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
        }
        .listStyle(.insetGrouped)
        .refreshable { await sensorViewModel.load() }
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
        case "leaf_wetness":
            return "Leaf wetness"
        case "gdd":
            return "Growing degree days"
        case "vpd":
            return "Vapor pressure deficit"
        default:
            return sensorType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Vineyard snapshot

    private var vineyardSnapshotCard: some View {
        let snapshot = currentVineyardSnapshot()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                snapshotTile(
                    title: "GDD today",
                    value: snapshot.gddText,
                    caption: "Base 50°F",
                    systemImage: "thermometer.sun",
                    tint: .orange
                )
                snapshotTile(
                    title: "VPD",
                    value: snapshot.vpdText,
                    caption: "Canopy stress",
                    systemImage: "humidity",
                    tint: .blue
                )
                snapshotTile(
                    title: "Powdery mildew",
                    value: snapshot.mildewRisk.label,
                    caption: "Risk index",
                    systemImage: "leaf",
                    tint: snapshot.mildewRisk.color
                )
                snapshotTile(
                    title: "Leaf wetness",
                    value: snapshot.leafWetnessText,
                    caption: "Hours today",
                    systemImage: "drop",
                    tint: .teal
                )
            }
            .padding(.vertical, 4)
        }
    }

    private func snapshotTile(
        title: String,
        value: String,
        caption: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.bold())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private struct VineyardSnapshot {
        let gddText: String
        let vpdText: String
        let leafWetnessText: String
        let mildewRisk: MildewRisk
    }

    private enum MildewRisk {
        case low, moderate, high, unknown

        var label: String {
            switch self {
            case .low: return "Low"
            case .moderate: return "Moderate"
            case .high: return "High"
            case .unknown: return "—"
            }
        }

        var color: Color {
            switch self {
            case .low: return .green
            case .moderate: return .orange
            case .high: return .red
            case .unknown: return .gray
            }
        }
    }

    private func currentVineyardSnapshot() -> VineyardSnapshot {
        let readings = sensorViewModel.devices.flatMap { $0.readings }
        let tempReading = readings.first { $0.sensorType == "temperature" }
        let humidityReading = readings.first { $0.sensorType == "humidity" }
        let leafWetnessReading = readings.first { $0.sensorType == "leaf_wetness" }

        let tempF = tempReading.map { temperatureInFahrenheit(value: $0.value, unit: $0.unit) }
        let humidity = humidityReading?.value

        let gddText: String = {
            guard let tempF else { return "—" }
            // Simple daily proxy: max(0, currentTemp - 50°F).
            // Real GDD uses (Tmax + Tmin)/2 - base, but for a snapshot
            // this gives a representative directional value.
            let gdd = max(0, tempF - 50)
            return String(format: "%.0f", gdd)
        }()

        let vpdText: String = {
            guard let tempF, let humidity else { return "—" }
            let tempC = (tempF - 32) * 5.0 / 9.0
            let svp = 0.6108 * exp((17.27 * tempC) / (tempC + 237.3))
            let vpd = svp * (1 - humidity / 100)
            return String(format: "%.2f kPa", vpd)
        }()

        let leafWetnessText: String = {
            guard let leafWetnessReading else { return "—" }
            let rounded = String(format: "%.0f", leafWetnessReading.value)
            return "\(rounded) \(leafWetnessReading.unit)"
        }()

        let mildewRisk: MildewRisk = {
            guard let tempF, let humidity else { return .unknown }
            // Powdery mildew thrives at 60-85°F with elevated humidity.
            let inTempRange = tempF >= 60 && tempF <= 85
            switch (inTempRange, humidity) {
            case (true, 80...): return .high
            case (true, 60..<80): return .moderate
            case (true, _): return .low
            case (false, _): return .low
            }
        }()

        return VineyardSnapshot(
            gddText: gddText,
            vpdText: vpdText,
            leafWetnessText: leafWetnessText,
            mildewRisk: mildewRisk
        )
    }

    private func temperatureInFahrenheit(value: Double, unit: String) -> Double {
        let normalized = unit.lowercased()
        if normalized.contains("c") && !normalized.contains("f") {
            return value * 9.0 / 5.0 + 32
        }
        return value
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
