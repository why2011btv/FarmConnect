import Foundation

@MainActor
final class BlockWeatherViewModel: ObservableObject {
    @Published var readingsByBlockId: [String: VineyardCanopyReading] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var loadedKey: String?

    func load(for blocks: [VineyardDemoBlock]) async {
        let key = blocks.map { "\($0.id):\($0.center.latitude):\($0.center.longitude)" }.joined(separator: "|")
        if key == loadedKey, !readingsByBlockId.isEmpty { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard !blocks.isEmpty else {
            readingsByBlockId = [:]
            loadedKey = key
            return
        }

        do {
            let points = blocks.map {
                BlockWeatherPoint(
                    blockId: $0.id,
                    latitude: $0.center.latitude,
                    longitude: $0.center.longitude
                )
            }
            let items = try await APIClient.shared.getBlockWeather(points: points)
            readingsByBlockId = Dictionary(uniqueKeysWithValues: items.map { ($0.blockId, $0.canopyReading) })
            loadedKey = key
        } catch {
            if isCancellationError(error) { return }
            errorMessage = "Weather unavailable: \(error.localizedDescription)"
        }
    }

    func invalidate() {
        loadedKey = nil
    }
}
