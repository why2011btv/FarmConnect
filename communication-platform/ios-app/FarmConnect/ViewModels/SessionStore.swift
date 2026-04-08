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

    func signIn(username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let auth = try await APIClient.shared.signIn(username: username, password: password)
            token = auth.token
            currentUser = auth.user
            APIClient.shared.setAuthToken(auth.token)
            UserDefaults.standard.set(auth.token, forKey: tokenKey)
        } catch {
            errorMessage = "Sign in failed: check username/password and try again."
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

    func logout() {
        token = nil
        currentUser = nil
        APIClient.shared.setAuthToken(nil)
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}
