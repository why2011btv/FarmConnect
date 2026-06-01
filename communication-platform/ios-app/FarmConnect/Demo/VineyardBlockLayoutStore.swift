import Foundation

@MainActor
final class VineyardBlockLayoutStore: ObservableObject {
    @Published private(set) var rectangles: [VineyardBlockRectangle]
    @Published private(set) var blockSettings: [String: VineyardBlockSettings]

    private static let rectanglesKey = "vineyard.demo.block.rectangles.v1"
    private static let settingsKey = "vineyard.demo.block.settings.v1"

    init() {
        rectangles = Self.loadRectangles() ?? VineyardDemoData.defaultRectangles
        blockSettings = Self.loadSettings() ?? VineyardDemoData.defaultBlockSettings
    }

    var blocks: [VineyardDemoBlock] {
        VineyardDemoData.makeBlocks(rectangles: rectangles, settings: blockSettings)
    }

    func rectangle(id: String) -> VineyardBlockRectangle? {
        rectangles.first { $0.id == id }
    }

    func settings(for id: String) -> VineyardBlockSettings {
        blockSettings[id] ?? .empty
    }

    func updateRectangle(id: String, _ mutate: (inout VineyardBlockRectangle) -> Void) {
        guard let index = rectangles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&rectangles[index])
        persistRectangles()
    }

    func setGrapeVariety(blockId: String, variety: GrapeVariety) {
        var settings = blockSettings[blockId] ?? .empty
        settings.grapeVariety = variety.rawValue
        blockSettings[blockId] = settings
        persistSettings()
    }

    func setRectangles(_ next: [VineyardBlockRectangle]) {
        rectangles = next
        persistRectangles()
    }

    func resetToDefaults() {
        rectangles = VineyardDemoData.defaultRectangles
        blockSettings = VineyardDemoData.defaultBlockSettings
        persistRectangles()
        persistSettings()
    }

    func resetBlock(id: String) {
        if let defaultRect = VineyardDemoData.defaultRectangles.first(where: { $0.id == id }),
           let index = rectangles.firstIndex(where: { $0.id == id }) {
            rectangles[index] = defaultRect
        }
        if let defaultSettings = VineyardDemoData.defaultBlockSettings[id] {
            blockSettings[id] = defaultSettings
        }
        persistRectangles()
        persistSettings()
    }

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rectangles),
              let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }

    func importJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([VineyardBlockRectangle].self, from: data),
              decoded.count == VineyardDemoData.defaultRectangles.count,
              Set(decoded.map(\.id)) == Set(VineyardDemoData.defaultRectangles.map(\.id))
        else { return false }
        rectangles = decoded
        persistRectangles()
        return true
    }

    private func persistRectangles() {
        guard let data = try? JSONEncoder().encode(rectangles) else { return }
        UserDefaults.standard.set(data, forKey: Self.rectanglesKey)
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(blockSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }

    private static func loadRectangles() -> [VineyardBlockRectangle]? {
        guard let data = UserDefaults.standard.data(forKey: rectanglesKey),
              let decoded = try? JSONDecoder().decode([VineyardBlockRectangle].self, from: data),
              decoded.count == VineyardDemoData.defaultRectangles.count
        else { return nil }
        return decoded
    }

    private static func loadSettings() -> [String: VineyardBlockSettings]? {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode([String: VineyardBlockSettings].self, from: data)
        else { return nil }
        return decoded
    }
}
