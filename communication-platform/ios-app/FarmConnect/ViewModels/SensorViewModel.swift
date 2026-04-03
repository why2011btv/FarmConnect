import Foundation

@MainActor
final class SensorViewModel: ObservableObject {
    @Published var devices: [SensorDeviceOverview] = []
    @Published var insights: [SensorInsight] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            devices = try await APIClient.shared.getSensorOverview()
            insights = try await APIClient.shared.getSensorInsights()
        } catch {
            errorMessage = "Failed to load sensors: \(error.localizedDescription)"
        }
    }
}
