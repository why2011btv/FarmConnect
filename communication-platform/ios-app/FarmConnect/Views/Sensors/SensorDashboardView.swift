import SwiftUI

struct SensorDashboardView: View {
    @EnvironmentObject private var sensorViewModel: SensorViewModel

    var body: some View {
        NavigationStack {
            Group {
                if sensorViewModel.isLoading {
                    ProgressView("Loading sensors...")
                } else if let error = sensorViewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                } else if sensorViewModel.devices.isEmpty {
                    ContentUnavailableView("No sensor devices", systemImage: "waveform.path.ecg")
                } else {
                    List(sensorViewModel.devices) { device in
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
                    .listStyle(.plain)
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
}
