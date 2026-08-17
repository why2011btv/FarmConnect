import SwiftUI

/// Two-step password reset: request a code by email, then enter it with a new password.
///
/// A code typed into the app rather than a tapped link, because a link would need Universal Links
/// and a verified web domain to reopen the app — a code works from any mail client on any device.
struct PasswordResetView: View {
    enum Step {
        case requestCode
        case enterCode
    }

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var code = ""
    @State private var newPassword = ""
    @State private var step: Step = .requestCode

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .requestCode:
                    Section {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("We'll email you a code to reset your password.")
                    }

                    Section {
                        Button {
                            Task {
                                if await session.requestPasswordReset(email: trimmedEmail) {
                                    step = .enterCode
                                }
                            }
                        } label: {
                            if session.isLoading {
                                ProgressView()
                            } else {
                                Text("Send reset code")
                            }
                        }
                        .disabled(trimmedEmail.isEmpty || session.isLoading)
                    }

                case .enterCode:
                    Section {
                        TextField("Reset code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        SecureField("New password", text: $newPassword)
                            .textContentType(.newPassword)
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Check your email")
                    } footer: {
                        // Careful wording: the server never confirms whether an address is
                        // registered, so we must not imply that an email definitely went out.
                        Text("If an account exists for \(trimmedEmail), a code is on its way. It expires in 30 minutes. Passwords must be at least 8 characters.")
                    }

                    Section {
                        Button {
                            Task {
                                let ok = await session.resetPassword(
                                    email: trimmedEmail,
                                    code: code,
                                    password: newPassword
                                )
                                if ok { dismiss() }
                            }
                        } label: {
                            if session.isLoading {
                                ProgressView()
                            } else {
                                Text("Reset password")
                            }
                        }
                        .disabled(code.isEmpty || newPassword.count < 8 || session.isLoading)

                        Button("Send a new code") {
                            Task { _ = await session.requestPasswordReset(email: trimmedEmail) }
                        }
                        .disabled(session.isLoading)
                    }
                }

                if let error = session.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
