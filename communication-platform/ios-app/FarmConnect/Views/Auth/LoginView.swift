import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var name = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("FarmConnect")
                    .font(.largeTitle.bold())
                Text("Sign in to access feed, chat, and posting")
                    .foregroundStyle(.secondary)

                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)

                Text("Use at least 6 characters. New name + password creates an account.")
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
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password
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
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || password.count < 6
                    || session.isLoading
                )
            }
            .padding()
        }
    }
}
