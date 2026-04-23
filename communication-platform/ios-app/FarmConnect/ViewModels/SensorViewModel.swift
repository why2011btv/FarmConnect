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
            if isCancellationError(error) { return }
            errorMessage = "Failed to load sensors: \(error.localizedDescription)"
        }
    }

    func dismissInsights(at offsets: IndexSet) {
        insights.remove(atOffsets: offsets)
    }

    func dismissInsight(id: String) {
        insights.removeAll { $0.id == id }
    }
}
