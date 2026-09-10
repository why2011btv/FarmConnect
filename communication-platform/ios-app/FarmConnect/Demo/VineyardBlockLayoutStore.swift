import Combine
import Foundation

@MainActor
final class VineyardBlockLayoutStore: ObservableObject {
    /// Which layout is currently displayed/edited. Demo (farmer-facing) is the launch default.
    @Published private(set) var mode: LayoutMode
    /// Both layouts at once. A write to one slot never touches the other.
    @Published private(set) var slots: LayoutSlots

    // Account/farm-scoped persistence. A layout created by one signed-in customer must never be
    // displayed to another account using the same iPhone.
    private static let demoSlotKeyPrefix = "vineyard.slot.demo.v3"
    private static let planningSlotKeyPrefix = "vineyard.slot.planning.v3"
    private static let modeKeyPrefix = "vineyard.layout.mode.v3"
    private var storageScope: String?
    private var farmId: String?
    private var syncTask: Task<Void, Never>?

    init() {
        slots = LayoutSlots(demo: VineyardDemoData.defaultDemoSlot, planning: .empty)
        mode = .planning
    }

    /// Loads only this account/farm's layout. Legacy unscoped layouts are deliberately ignored
    /// because they cannot safely be attributed after an account switch.
    func configure(userId: String, farmId: String?) async {
        let scope = Self.safeScope("\(userId)|\(farmId ?? "no-farm")")
        guard storageScope != scope else { return }
        syncTask?.cancel()
        storageScope = scope
        self.farmId = farmId

        slots = LayoutSlots(
            demo: loadSlot(forKey: demoSlotKey) ?? VineyardDemoData.defaultDemoSlot,
            planning: loadSlot(forKey: planningSlotKey) ?? .empty
        )
        mode = loadMode() ?? .planning
        persist(slot: slots.demo, forKey: demoSlotKey)

        guard let farmId else { return }
        do {
            if let shared = try await APIClient.shared.getVineyardLayout(farmId: farmId) {
                slots.planning = shared
                persist(slot: shared, forKey: planningSlotKey)
            } else if !slots.planning.rectangles.isEmpty {
                // One-time migration: make a layout created by an older app build available to
                // every device that belongs to this farm.
                try await APIClient.shared.setVineyardLayout(slots.planning, farmId: farmId)
            }
        } catch {
            // Keep the cached layout usable offline. The next edit or app launch retries sync.
        }
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
        persist(slot: slots.planning, forKey: planningSlotKey)
        schedulePlanningSync()
        if mode != .planning {
            mode = .planning
            persistMode()
        }
    }

    /// Copy the current planning layout into the demo slot so it can be hand-polished for a demo.
    /// A deep value copy: the two slots remain fully independent afterwards.
    /// Note: after promotion, demo "Reset to defaults" still reverts to the bundled sample layout.
    func promoteActiveLayoutToDemo() {
        slots.demo = slots.planning
        persist(slot: slots.demo, forKey: demoSlotKey)
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
        case .demo: persist(slot: slots.demo, forKey: demoSlotKey)
        case .planning:
            persist(slot: slots.planning, forKey: planningSlotKey)
            schedulePlanningSync()
        }
    }

    private func schedulePlanningSync() {
        guard let farmId else { return }
        let layout = slots.planning
        syncTask?.cancel()
        syncTask = Task {
            // Coalesce slider and repeated nudge updates into one server write.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? await APIClient.shared.setVineyardLayout(layout, farmId: farmId)
        }
    }

    private func persist(slot: LayoutSlot, forKey key: String?) {
        guard let key else { return }
        guard let data = try? JSONEncoder().encode(slot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func persistMode() {
        guard let modeKey else { return }
        guard let data = try? JSONEncoder().encode(mode) else { return }
        UserDefaults.standard.set(data, forKey: modeKey)
    }

    private func loadSlot(forKey key: String?) -> LayoutSlot? {
        guard let key else { return nil }
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(LayoutSlot.self, from: data)
        else { return nil }
        return decoded
    }

    private func loadMode() -> LayoutMode? {
        guard let modeKey,
              let data = UserDefaults.standard.data(forKey: modeKey),
              let decoded = try? JSONDecoder().decode(LayoutMode.self, from: data)
        else { return nil }
        return decoded
    }

    private var demoSlotKey: String? { storageScope.map { "\(Self.demoSlotKeyPrefix).\($0)" } }
    private var planningSlotKey: String? { storageScope.map { "\(Self.planningSlotKeyPrefix).\($0)" } }
    private var modeKey: String? { storageScope.map { "\(Self.modeKeyPrefix).\($0)" } }

    private static func safeScope(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

}
