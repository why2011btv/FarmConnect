import SwiftUI

struct LoginView: View {
    enum AuthMode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case signUp = "Sign Up"

        var id: String { rawValue }
    }

    @EnvironmentObject private var session: SessionStore
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showResetSheet = false

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deliberately loose: real address validation is the server's job, and a client-side regex
    /// that rejects a valid address is worse than one round trip.
    private var emailLooksValid: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }

    private static let minPasswordLength = 8
    private var passwordMeetsRequirement: Bool { password.count >= Self.minPasswordLength }

    /// Live password-requirement feedback for sign-up: neutral hint when empty, a red warning with
    /// the current length while too short, and a green confirmation once it qualifies. This is why
    /// the Sign Up button is (in)active, shown plainly instead of leaving the user guessing.
    @ViewBuilder
    private var passwordRequirementHint: some View {
        if mode == .signUp {
            let ok = passwordMeetsRequirement
            let empty = password.isEmpty
            let icon = empty ? "info.circle"
                : (ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            let message = empty ? "Use at least \(Self.minPasswordLength) characters"
                : (ok ? "Password looks good"
                     : "Password must be at least \(Self.minPasswordLength) characters (\(password.count)/\(Self.minPasswordLength))")
            let color: Color = empty ? .secondary : (ok ? .green : .red)

            Label(message, systemImage: icon)
                .font(.footnote)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.15), value: ok)
                .animation(.easeInOut(duration: 0.15), value: empty)
        }
    }

    private var canSubmit: Bool {
        guard emailLooksValid, !session.isLoading else { return false }
        switch mode {
        case .signIn:
            return !password.isEmpty
        case .signUp:
            return passwordMeetsRequirement && !trimmedDisplayName.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Persephone's Basket")
                        .font(.largeTitle.bold())
                    Text("Sign in to your vineyard dashboard")
                        .foregroundStyle(.secondary)

                    Picker("Auth mode", selection: $mode) {
                        ForEach(AuthMode.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .textInputAutocapitalization(.never)

                    passwordRequirementHint

                    if mode == .signUp {
                        TextField("Your name", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)

                        Text("After signing up you'll enter the access code that came with your sensors.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = session.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task {
                            if mode == .signIn {
                                await session.signIn(email: trimmedEmail, password: password)
                            } else {
                                await session.signUp(
                                    email: trimmedEmail,
                                    password: password,
                                    displayName: trimmedDisplayName
                                )
                            }
                        }
                    } label: {
                        if session.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(mode.rawValue)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            session.errorMessage = nil
                            showResetSheet = true
                        }
                        .font(.footnote)
                    }
                }
                .padding()
            }
            .sheet(isPresented: $showResetSheet) {
                PasswordResetView(initialEmail: trimmedEmail)
                    .environmentObject(session)
            }
            .onChange(of: mode) { _, _ in
                session.errorMessage = nil
            }
        }
    }
}
