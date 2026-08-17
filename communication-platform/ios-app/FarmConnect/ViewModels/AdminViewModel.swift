import Foundation

@MainActor
final class AdminViewModel: ObservableObject {
    @Published var farms: [AdminFarmSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadFarms() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            farms = try await APIClient.shared.adminListFarms()
        } catch {
            errorMessage = friendlyMessage(error, fallback: "Couldn't load farms.")
        }
    }

    /// Provisions a customer. The returned secrets exist only in this value — they are not stored
    /// server-side and cannot be fetched again, so the caller must display them before dismissing.
    func createFarm(name: String, nodeCount: Int) async -> AdminProvisionResponse? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await APIClient.shared.adminCreateFarm(name: name, nodeCount: nodeCount)
            await loadFarms()
            return result
        } catch {
            errorMessage = friendlyMessage(error, fallback: "Couldn't create that farm.")
            return nil
        }
    }
}

@MainActor
final class AdminFarmDetailViewModel: ObservableObject {
    @Published var detail: AdminFarmDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let farmId: String

    init(farmId: String) {
        self.farmId = farmId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await APIClient.shared.adminFarmDetail(farmId: farmId)
        } catch {
            errorMessage = friendlyMessage(error, fallback: "Couldn't load that farm.")
        }
    }

    func issueCode(label: String?, maxUses: Int?) async -> String? {
        errorMessage = nil
        do {
            let code = try await APIClient.shared.adminIssueCode(farmId: farmId, label: label, maxUses: maxUses)
            await load()
            return code
        } catch {
            errorMessage = friendlyMessage(error, fallback: "Couldn't issue a code.")
            return nil
        }
    }

    func revokeCode(_ codeId: String) async {
        errorMessage = nil
        do {
            try await APIClient.shared.adminRevokeCode(farmId: farmId, codeId: codeId)
            await load()
        } catch {
            errorMessage = friendlyMessage(error, fallback: "Couldn't revoke that code.")
        }
    }

    func removeMember(_ userId: String) async {
        errorMessage = nil
        do {
            try await APIClient.shared.adminRemoveMember(farmId: farmId, userId: userId)
            await load()
        } catch {
            errorMessage = friendlyMessage(error, fallback: "Couldn't remove that person.")
        }
    }

    func rotateKey(deviceId: String) async -> AdminRotateKeyResponse? {
        errorMessage = nil
        do {
            return try await APIClient.shared.adminRotateDeviceKey(deviceId: deviceId)
        } catch {
            errorMessage = friendlyMessage(error, fallback: "Couldn't rotate that key.")
            return nil
        }
    }
}

/// Prefers the server's own message, which is written for humans, over a generic fallback.
private func friendlyMessage(_ error: Error, fallback: String) -> String {
    if case APIError.serverMessage(_, let text) = error, !text.isEmpty { return text }
    return fallback
}
