import SwiftUI

/// Onboarding gate shown when a signed-in user belongs to no farm yet.
///
/// The code is exchanged once for permanent membership, so it is never stored on the phone —
/// after this screen the user's normal session is what grants access to their sensors.
struct AccessCodeView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var code = ""
    @State private var claimedFarmName: String?

    private var canSubmit: Bool {
        AccessCodeFormatter.isComplete(code) && !session.isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text("Enter your access code")
                    .font(.title2.bold())

                Text("Your access code came printed on the card in the box with your sensors. It connects this account to your farm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // The "PB-" prefix is a fixed label, not editable text, so the characters the
                // user types are unambiguously the code body.
                HStack(spacing: 6) {
                    Text("\(AccessCodeFormatter.displayPrefix)-")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.secondary)

                    TextField("XXXX-XXXX-XXXX-XXXX", text: $code)
                        .font(.system(.title3, design: .monospaced))
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .onChange(of: code) { _, newValue in
                            let formatted = AccessCodeFormatter.formatBody(newValue)
                            if formatted != newValue { code = formatted }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.4))
                )

                if let error = session.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        if let farm = await session.claimFarm(code: code) {
                            claimedFarmName = farm.name
                        }
                    }
                } label: {
                    if session.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Connect my farm").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Text("Don't have a code? Contact us and we'll send you one for your farm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Escape hatch: someone who signed into the wrong account needs a way back out
                // of this screen, which otherwise blocks the whole app.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") { session.logout() }
                }
            }
            .alert("You're connected", isPresented: .constant(claimedFarmName != nil)) {
                Button("Continue") { claimedFarmName = nil }
            } message: {
                Text("This account now has access to \(claimedFarmName ?? "your farm").")
            }
        }
    }

}
