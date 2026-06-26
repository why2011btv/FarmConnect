import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var token: String?
    @Published var currentUser: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let tokenKey = "farmconnect.auth.token"

    var isAuthenticated: Bool {
        token != nil && currentUser != nil
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
        } catch {
            logout()
        }
    }

    func signIn(username: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let auth = try await APIClient.shared.signIn(username: username)
            token = auth.token
            currentUser = auth.user
            APIClient.shared.setAuthToken(auth.token)
            UserDefaults.standard.set(auth.token, forKey: tokenKey)
        } catch {
            errorMessage = "Sign in failed: check username and try again."
        }
    }

    func signUp(username: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let auth = try await APIClient.shared.signUp(
                username: username,
                password: password,
                displayName: displayName
            )
            token = auth.token
            currentUser = auth.user
            APIClient.shared.setAuthToken(auth.token)
            UserDefaults.standard.set(auth.token, forKey: tokenKey)
        } catch {
            errorMessage = "Sign up failed: username may be taken or input is invalid."
        }
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
        APIClient.shared.setAuthToken(nil)
        UserDefaults.standard.removeObject(forKey: tokenKey)
        if let tokenToInvalidate {
            Task.detached {
                try? await APIClient.shared.signOutSession(token: tokenToInvalidate)
            }
        }
    }
}
