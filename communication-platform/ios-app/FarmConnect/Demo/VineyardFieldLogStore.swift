import Foundation

/// Local demo field log: bundled entries plus user-added rows (UserDefaults).
@MainActor
final class VineyardFieldLogStore: ObservableObject {
    static let shared = VineyardFieldLogStore()

    @Published private(set) var entries: [VineyardFieldLogEntry] = []

    private let userEntriesKey = "farmconnect.vineyardFieldLog.userEntries"

    private init() {
        reload()
    }

    func reload() {
        let user = loadUserEntries()
        let merged = VineyardFieldLogDemoData.bundled + user
        entries = merged.sorted { $0.createdAt > $1.createdAt }
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
        guard let data = UserDefaults.standard.data(forKey: userEntriesKey) else { return [] }
        return (try? JSONDecoder().decode([VineyardFieldLogEntry].self, from: data)) ?? []
    }

    private func saveUserEntries(_ items: [VineyardFieldLogEntry]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: userEntriesKey)
        }
    }
}
