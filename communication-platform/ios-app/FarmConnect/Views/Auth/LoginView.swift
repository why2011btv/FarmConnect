import SwiftUI

struct LoginView: View {
    enum AuthMode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Sign Up"

        var id: String { rawValue }
    }

    @EnvironmentObject private var session: SessionStore
    @State private var mode: AuthMode = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("FarmAlert")
                    .font(.largeTitle.bold())
                Text("Use your account to continue")
                    .foregroundStyle(.secondary)

                Picker("Auth mode", selection: $mode) {
                    ForEach(AuthMode.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)

                if mode == .signUp {
                    TextField("Display name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.words)
                }

                Text(mode == .signIn
                     ? "Sign in with an existing username."
                     : "Create a new account with unique username and display name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let error = session.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Button {
                    Task {
                        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
                        if mode == .signIn {
                            await session.signIn(
                                username: normalizedUsername,
                                password: password
                            )
                        } else {
                            await session.signUp(
                                username: normalizedUsername,
                                password: password,
                                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        }
                    }
                } label: {
                    if session.isLoading {
                        ProgressView()
                    } else {
                        Text(mode.rawValue)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || password.count < 6
                    || (mode == .signUp && displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    || session.isLoading
                )
            }
            .padding()
        }
    }
}
