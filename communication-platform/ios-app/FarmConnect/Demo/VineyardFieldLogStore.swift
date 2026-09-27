import Foundation

/// Farm-scoped field logs synchronized with the cloud API.
@MainActor
final class VineyardFieldLogStore: ObservableObject {
    static let shared = VineyardFieldLogStore()

    @Published private(set) var entries: [VineyardFieldLogEntry] = []

    private let legacyKeyPrefix = "farmconnect.vineyardFieldLog.userEntries"
    private var activeUserId: String?
    private var activeFarmId: String?

    private init() {}

    func configure(userId: String, farmId: String?) async {
        guard activeUserId != userId || activeFarmId != farmId else { return }
        activeUserId = userId
        activeFarmId = farmId
        guard let farmId else { entries = []; return }

        let legacy = loadLegacyEntries(userId: userId)
        do {
            entries = try await APIClient.shared.getFieldLogs(farmId: farmId).sorted { $0.createdAt > $1.createdAt }
            // Preserve records made by older builds, but only migrate them into an empty farm.
            if entries.isEmpty, !legacy.isEmpty {
                for entry in legacy { try? await APIClient.shared.addFieldLog(farmId: farmId, entry: entry) }
                entries = try await APIClient.shared.getFieldLogs(farmId: farmId).sorted { $0.createdAt > $1.createdAt }
                UserDefaults.standard.removeObject(forKey: legacyKey(userId: userId))
            }
        } catch {
            // Keep legacy entries visible until the server is reachable.
            entries = legacy.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func reload() async {
        guard let farmId = activeFarmId else { return }
        if let loaded = try? await APIClient.shared.getFieldLogs(farmId: farmId) {
            entries = loaded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func add(_ entry: VineyardFieldLogEntry) async {
        guard !entry.isBundledDemo, let farmId = activeFarmId else { return }
        do {
            try await APIClient.shared.addFieldLog(farmId: farmId, entry: entry)
            await reload()
        } catch {
            // Do not reintroduce a second local source of truth. The caller can retry by reopening.
        }
    }

    func delete(_ entry: VineyardFieldLogEntry) async {
        guard !entry.isBundledDemo, let farmId = activeFarmId else { return }
        do {
            try await APIClient.shared.deleteFieldLog(farmId: farmId, id: entry.id)
            entries.removeAll { $0.id == entry.id }
        } catch {
            // Leave the record visible if the server rejected the delete.
        }
    }

    func entries(kind: VineyardLogKind?) -> [VineyardFieldLogEntry] {
        guard let kind else { return entries }
        return entries.filter { $0.kind == kind }
    }

    private func loadLegacyEntries(userId: String) -> [VineyardFieldLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: legacyKey(userId: userId)) else { return [] }
        return (try? JSONDecoder().decode([VineyardFieldLogEntry].self, from: data)) ?? []
    }

    private func legacyKey(userId: String) -> String { "\(legacyKeyPrefix).\(userId)" }
}
