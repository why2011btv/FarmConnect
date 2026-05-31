import Foundation

@MainActor
final class VineyardBlockLayoutStore: ObservableObject {
    @Published private(set) var rectangles: [VineyardBlockRectangle]

    private static let storageKey = "vineyard.demo.block.rectangles.v1"

    init() {
        rectangles = Self.loadFromDisk() ?? VineyardDemoData.defaultRectangles
    }

    var blocks: [VineyardDemoBlock] {
        VineyardDemoData.makeBlocks(rectangles: rectangles)
    }

    func rectangle(id: String) -> VineyardBlockRectangle? {
        rectangles.first { $0.id == id }
    }

    func updateRectangle(id: String, _ mutate: (inout VineyardBlockRectangle) -> Void) {
        guard let index = rectangles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&rectangles[index])
        persist()
    }

    func setRectangles(_ next: [VineyardBlockRectangle]) {
        rectangles = next
        persist()
    }

    func resetToDefaults() {
        rectangles = VineyardDemoData.defaultRectangles
        persist()
    }

    func resetBlock(id: String) {
        guard let defaultRect = VineyardDemoData.defaultRectangles.first(where: { $0.id == id }),
              let index = rectangles.firstIndex(where: { $0.id == id })
        else { return }
        rectangles[index] = defaultRect
        persist()
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
        persist()
        return true
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rectangles) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func loadFromDisk() -> [VineyardBlockRectangle]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([VineyardBlockRectangle].self, from: data),
              decoded.count == VineyardDemoData.defaultRectangles.count
        else { return nil }
        return decoded
    }
}
