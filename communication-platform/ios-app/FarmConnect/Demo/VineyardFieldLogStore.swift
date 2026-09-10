import Foundation

/// Local field log containing only entries created by the user on this device.
@MainActor
final class VineyardFieldLogStore: ObservableObject {
    static let shared = VineyardFieldLogStore()

    @Published private(set) var entries: [VineyardFieldLogEntry] = []

    private let userEntriesKeyPrefix = "farmconnect.vineyardFieldLog.userEntries"
    private var activeUserId: String?

    private init() {
        entries = []
    }

    /// Selects account-isolated local storage. The legacy unscoped/demo key is intentionally not
    /// migrated because its entries cannot safely be attributed to the currently signed-in user.
    func configure(userId: String) {
        guard activeUserId != userId else { return }
        activeUserId = userId
        reload()
    }

    func reload() {
        entries = loadUserEntries().sorted { $0.createdAt > $1.createdAt }
    }

    func add(_ entry: VineyardFieldLogEntry) {
        guard !entry.isBundledDemo else { return }
        var user = loadUserEntries()
        user.insert(entry, at: 0)
        saveUserEntries(user)
        reload()
    }

    func delete(_ entry: VineyardFieldLogEntry) {
        guard !entry.isBundledDemo else { return }
        var user = loadUserEntries()
        user.removeAll { $0.id == entry.id }
        saveUserEntries(user)
        reload()
    }

    func entries(kind: VineyardLogKind?) -> [VineyardFieldLogEntry] {
        guard let kind else { return entries }
        return entries.filter { $0.kind == kind }
    }

    // MARK: - Persistence

    private func loadUserEntries() -> [VineyardFieldLogEntry] {
        guard let userEntriesKey,
              let data = UserDefaults.standard.data(forKey: userEntriesKey) else { return [] }
        return (try? JSONDecoder().decode([VineyardFieldLogEntry].self, from: data)) ?? []
    }

    private func saveUserEntries(_ items: [VineyardFieldLogEntry]) {
        if let userEntriesKey, let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: userEntriesKey)
        }
    }

    private var userEntriesKey: String? {
        activeUserId.map { "\(userEntriesKeyPrefix).\($0)" }
    }
}
