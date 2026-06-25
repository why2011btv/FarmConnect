import Combine
import Foundation

@MainActor
final class VineyardBlockLayoutStore: ObservableObject {
    /// Which layout is currently displayed/edited. Demo (farmer-facing) is the launch default.
    @Published private(set) var mode: LayoutMode
    /// Both layouts at once. A write to one slot never touches the other.
    @Published private(set) var slots: LayoutSlots

    // Per-slot persistence keys (v2). A planning write only re-encodes the planning key, etc.
    private static let demoSlotKey = "vineyard.slot.demo.v2"
    private static let planningSlotKey = "vineyard.slot.planning.v2"
    private static let modeKey = "vineyard.layout.mode.v2"

    // Legacy v1 keys — read once for migration, then left in place for one release.
    private static let legacyRectanglesKey = "vineyard.demo.block.rectangles.v1"
    private static let legacySettingsKey = "vineyard.demo.block.settings.v1"

    init() {
        let demoSlot = Self.loadSlot(forKey: Self.demoSlotKey)
            ?? Self.migrateDemoFromV1()
            ?? VineyardDemoData.defaultDemoSlot
        let planningSlot = Self.loadSlot(forKey: Self.planningSlotKey) ?? .empty

        slots = LayoutSlots(demo: demoSlot, planning: planningSlot)
        mode = Self.loadMode() ?? .demo

        // Persist the (possibly migrated) demo slot so future launches skip migration.
        persist(slot: slots.demo, forKey: Self.demoSlotKey)
    }

    // MARK: - Active-slot read facades (get-only; views observe $slots / $mode)

    private var activeSlot: LayoutSlot { slots[mode] }

    var rectangles: [VineyardBlockRectangle] { activeSlot.rectangles }
    var blockSettings: [String: VineyardBlockSettings] { activeSlot.blockSettings }
    var activeProfile: VineyardProfile? { activeSlot.profile }

    var blocks: [VineyardDemoBlock] {
        VineyardDemoData.makeBlocks(rectangles: activeSlot.rectangles, settings: activeSlot.blockSettings)
    }

    func rectangle(id: String) -> VineyardBlockRectangle? {
        activeSlot.rectangles.first { $0.id == id }
    }

    func settings(for id: String) -> VineyardBlockSettings {
        activeSlot.blockSettings[id] ?? .empty
    }

    // MARK: - Mode switching

    func setMode(_ next: LayoutMode) {
        guard next != mode else { return }
        mode = next
        persistMode()
    }

    // MARK: - Mutations (all funnel through mutateActiveSlot)

    /// Mutate the active slot in place and persist ONLY that slot's key.
    /// `persist` defaults to true; pass false during a continuous drag and persist on drag-end.
    private func mutateActiveSlot(persist shouldPersist: Bool = true, _ body: (inout LayoutSlot) -> Void) {
        body(&slots[mode])
        if shouldPersist { persistActiveSlot() }
    }

    func updateRectangle(
        id: String,
        persist shouldPersist: Bool = true,
        _ mutate: (inout VineyardBlockRectangle) -> Void
    ) {
        mutateActiveSlot(persist: shouldPersist) { slot in
            guard let index = slot.rectangles.firstIndex(where: { $0.id == id }) else { return }
            mutate(&slot.rectangles[index])
        }
    }

    func setGrapeVariety(blockId: String, variety: GrapeVariety) {
        mutateActiveSlot { slot in
            var settings = slot.blockSettings[blockId] ?? .empty
            settings.grapeVariety = variety.rawValue
            slot.blockSettings[blockId] = settings
        }
    }

    func setRectangles(_ next: [VineyardBlockRectangle]) {
        mutateActiveSlot { $0.rectangles = next }
    }

    /// Persist the active slot explicitly (e.g. at the end of a drag that mutated without persisting).
    func commitActiveSlot() {
        persistActiveSlot()
    }

    func resetToDefaults() {
        switch mode {
        case .demo:
            slots.demo = VineyardDemoData.defaultDemoSlot
        case .planning:
            slots.planning = .empty
        }
        persistActiveSlot()
    }

    func resetBlock(id: String) {
        // Reset is only meaningful for curated demo blocks (which have bundled defaults). For
        // auto-generated planning blocks there is no per-block default, so this is a no-op there.
        guard mode == .demo else { return }
        mutateActiveSlot { slot in
            if let defaultRect = VineyardDemoData.defaultRectangles.first(where: { $0.id == id }),
               let index = slot.rectangles.firstIndex(where: { $0.id == id }) {
                slot.rectangles[index] = defaultRect
            }
            if let defaultSettings = VineyardDemoData.defaultBlockSettings[id] {
                slot.blockSettings[id] = defaultSettings
            }
        }
    }

    // MARK: - Auto-generation + promotion

    /// The ONLY write path for the auto-generation flow. Writes the planning slot exclusively.
    func installPlanningLayout(
        rectangles: [VineyardBlockRectangle],
        settings: [String: VineyardBlockSettings] = [:],
        profile: VineyardProfile
    ) {
        slots.planning = LayoutSlot(rectangles: rectangles, blockSettings: settings, profile: profile)
        persist(slot: slots.planning, forKey: Self.planningSlotKey)
        if mode != .planning {
            mode = .planning
            persistMode()
        }
    }

    /// Copy the current planning layout into the demo slot so it can be hand-polished for a demo.
    /// A deep value copy: the two slots remain fully independent afterwards.
    /// Note: after promotion, demo "Reset to defaults" still reverts to the bundled Running Brook layout.
    func promoteActiveLayoutToDemo() {
        slots.demo = slots.planning
        persist(slot: slots.demo, forKey: Self.demoSlotKey)
    }

    // MARK: - Import / export (active slot)

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(activeSlot.rectangles),
              let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }

    @discardableResult
    func importJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([VineyardBlockRectangle].self, from: data),
              !decoded.isEmpty
        else { return false }
        // Reject duplicate ids (would make ForEach/selection ambiguous).
        guard Set(decoded.map(\.id)).count == decoded.count else { return false }
        setRectangles(decoded)
        return true
    }

    // MARK: - Persistence helpers

    private func persistActiveSlot() {
        switch mode {
        case .demo: persist(slot: slots.demo, forKey: Self.demoSlotKey)
        case .planning: persist(slot: slots.planning, forKey: Self.planningSlotKey)
        }
    }

    private func persist(slot: LayoutSlot, forKey key: String) {
        guard let data = try? JSONEncoder().encode(slot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func persistMode() {
        guard let data = try? JSONEncoder().encode(mode) else { return }
        UserDefaults.standard.set(data, forKey: Self.modeKey)
    }

    private static func loadSlot(forKey key: String) -> LayoutSlot? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(LayoutSlot.self, from: data)
        else { return nil }
        return decoded
    }

    private static func loadMode() -> LayoutMode? {
        guard let data = UserDefaults.standard.data(forKey: modeKey),
              let decoded = try? JSONDecoder().decode(LayoutMode.self, from: data)
        else { return nil }
        return decoded
    }

    /// One-way migration of the v1 demo layout into a v2 demo slot. The caller only invokes this
    /// when the v2 demo key is absent. Returns nil when there's no usable v1 data (then the caller
    /// falls back to the bundled Running Brook defaults).
    private static func migrateDemoFromV1() -> LayoutSlot? {
        let rectangles: [VineyardBlockRectangle]? = {
            guard let data = UserDefaults.standard.data(forKey: legacyRectanglesKey) else { return nil }
            return try? JSONDecoder().decode([VineyardBlockRectangle].self, from: data)
        }()

        guard let rectangles, !rectangles.isEmpty else { return nil }

        let settings: [String: VineyardBlockSettings]? = {
            guard let data = UserDefaults.standard.data(forKey: legacySettingsKey) else { return nil }
            return try? JSONDecoder().decode([String: VineyardBlockSettings].self, from: data)
        }()

        // Rectangles present but settings missing/garbled -> use default grape varieties so the
        // farmer-facing layout never shows blank/wrong varieties.
        return LayoutSlot(
            rectangles: rectangles,
            blockSettings: settings ?? VineyardDemoData.defaultBlockSettings,
            profile: nil
        )
    }
}
