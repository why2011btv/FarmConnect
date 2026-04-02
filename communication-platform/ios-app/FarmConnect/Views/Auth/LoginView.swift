import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var name = ""

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

                if let error = session.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Button {
                    Task { await session.login(name: name.trimmingCharacters(in: .whitespacesAndNewlines)) }
                } label: {
                    if session.isLoading {
                        ProgressView()
                    } else {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isLoading)
            }
            .padding()
        }
    }
}
