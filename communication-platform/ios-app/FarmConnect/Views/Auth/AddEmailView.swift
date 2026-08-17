import SwiftUI

/// Prompt for accounts created before email login existed.
///
/// Not a hard gate: these customers can already use the app, they just have no way to recover a
/// forgotten password until an address is on file. Skipping is remembered for the session so the
/// prompt doesn't nag on every launch, but it returns next time until an address is added.
struct AddEmailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var emailLooksValid: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Your current password", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Add your email")
                } footer: {
                    // Say plainly why the password is needed, or it reads as a pointless hurdle.
                    Text("Without an email address we can't help you reset a forgotten password. We ask for your password because this address becomes the way you recover your account.")
                }

                if let error = session.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task {
                            if await session.addEmail(email: trimmedEmail, password: password) {
                                dismiss()
                            }
                        }
                    } label: {
                        if session.isLoading {
                            ProgressView()
                        } else {
                            Text("Save email")
                        }
                    }
                    .disabled(!emailLooksValid || password.isEmpty || session.isLoading)
                }
            }
            .navigationTitle("One more thing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }
}
