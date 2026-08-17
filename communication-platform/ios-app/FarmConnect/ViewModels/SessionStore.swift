import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var token: String?
    @Published var currentUser: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Farms the signed-in user has access to. Empty after `farmsLoaded` means they have not
    /// redeemed an access code yet and should be sent to the access-code screen.
    @Published var farms: [Farm] = []
    @Published var farmsLoaded = false

    private let tokenKey = "farmconnect.auth.token"

    var isAuthenticated: Bool {
        token != nil && currentUser != nil
    }

    var isAdmin: Bool { currentUser?.isAdmin ?? false }

    /// Accounts created before email login have no address, which means no password reset. We
    /// prompt for one rather than blocking: they can still use the app, they just can't recover
    /// their account until they add it.
    var needsEmail: Bool {
        isAuthenticated && (currentUser?.email ?? "").isEmpty
    }

    /// True only once we actually know the farm list is empty — otherwise a slow network would
    /// flash the access-code screen at a customer who already has a farm.
    ///
    /// Staff are exempt: an admin has no farm until they provision one, and the screen where they
    /// do that lives behind this gate.
    var needsFarmAccess: Bool {
        isAuthenticated && farmsLoaded && farms.isEmpty && !isAdmin
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: tokenKey) {
            token = saved
            APIClient.shared.setAuthToken(saved)
        }
    }

    func restoreSessionIfPossible() async {
        guard token != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            currentUser = try await APIClient.shared.me()
            errorMessage = nil
            await loadFarms()
        } catch {
            logout()
        }
    }

    /// Refreshes farm membership. Failures leave `farmsLoaded` untouched so a network blip does
    /// not bounce a signed-in user into onboarding.
    func loadFarms() async {
        guard isAuthenticated else { return }
        do {
            farms = try await APIClient.shared.getFarms()
            farmsLoaded = true
        } catch {
            // Keep whatever we had; the dashboard will retry on next appearance.
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let auth = try await APIClient.shared.signIn(email: email, password: password)
            applySession(auth)
            await loadFarms()
        } catch {
            errorMessage = message(from: error, fallback: "Sign in failed: check your email and password and try again.")
        }
    }

    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let auth = try await APIClient.shared.signUp(email: email, password: password, displayName: displayName)
            applySession(auth)
            await loadFarms()
        } catch {
            errorMessage = message(from: error, fallback: "Sign up failed: that email may already be registered.")
        }
    }

    /// Requests a reset code. Returns true whenever the request was accepted — the server does not
    /// reveal whether the address is registered, so the UI must not claim it was.
    func requestPasswordReset(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await APIClient.shared.requestPasswordReset(email: email)
            return true
        } catch {
            errorMessage = message(from: error, fallback: "Couldn't send a reset code. Try again.")
            return false
        }
    }

    func resetPassword(email: String, code: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let auth = try await APIClient.shared.resetPassword(email: email, code: code, password: password)
            applySession(auth)
            await loadFarms()
            return true
        } catch {
            errorMessage = message(from: error, fallback: "That reset code is invalid or has expired.")
            return false
        }
    }

    /// Redeems the access code that shipped with the customer's hardware.
    func claimFarm(code: String) async -> ClaimedFarm? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let farm = try await APIClient.shared.claimFarm(code: code)
            await loadFarms()
            return farm
        } catch {
            errorMessage = message(from: error, fallback: "That access code isn't valid.")
            return nil
        }
    }

    /// Adds an email to an account that lacks one. Returns true on success.
    func addEmail(email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            currentUser = try await APIClient.shared.setEmail(email: email, password: password)
            return true
        } catch {
            errorMessage = message(from: error, fallback: "Couldn't save that email address.")
            return false
        }
    }

    private func applySession(_ auth: AuthResponse) {
        token = auth.token
        currentUser = auth.user
        errorMessage = nil
        farms = []
        farmsLoaded = false
        APIClient.shared.setAuthToken(auth.token)
        UserDefaults.standard.set(auth.token, forKey: tokenKey)
    }

    /// Prefers the server's own message (which is written for end users) over a generic fallback.
    private func message(from error: Error, fallback: String) -> String {
        if case APIError.serverMessage(_, let text) = error, !text.isEmpty {
            return text
        }
        return fallback
    }

    /// Permanently deletes the account on the server, then clears the local session.
    /// Unlike `logout()`, this awaits the server so failures can be surfaced to the user.
    /// Returns true on success.
    func deleteAccount() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await APIClient.shared.deleteAccount()
            token = nil
            currentUser = nil
            farms = []
            farmsLoaded = false
            APIClient.shared.setAuthToken(nil)
            UserDefaults.standard.removeObject(forKey: tokenKey)
            return true
        } catch {
            errorMessage = "Couldn't delete your account. Please try again."
            return false
        }
    }

    /// Clears the local session immediately and invalidates the token on the
    /// server in the background. We don't `await` the server call so that
    /// logout feels instant even on flaky networks.
    func logout() {
        let tokenToInvalidate = token
        token = nil
        currentUser = nil
        farms = []
        farmsLoaded = false
        APIClient.shared.setAuthToken(nil)
        UserDefaults.standard.removeObject(forKey: tokenKey)
        if let tokenToInvalidate {
            Task.detached {
                try? await APIClient.shared.signOutSession(token: tokenToInvalidate)
            }
        }
    }
}
