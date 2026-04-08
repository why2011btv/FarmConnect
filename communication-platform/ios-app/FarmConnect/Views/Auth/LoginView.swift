import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("FarmConnect")
                    .font(.largeTitle.bold())
                Text("Sign in with username and password")
                    .foregroundStyle(.secondary)

                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)

                TextField("Display name (only for first-time signup)", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                Text("New username creates an account. Existing username requires the correct password.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let error = session.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Button {
                    Task {
                        await session.login(
                            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password,
                            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                } label: {
                    if session.isLoading {
                        ProgressView()
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || password.count < 6
                    || session.isLoading
                )
            }
            .padding()
        }
    }
}
