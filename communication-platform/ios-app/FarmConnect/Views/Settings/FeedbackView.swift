import SwiftUI
import UIKit

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var category: FeedbackCategory = .idea
    @State private var rating = 0
    @State private var message = ""
    @State private var includeDiagnostics = true
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?

    private let maximumMessageLength = 2_000

    var body: some View {
        NavigationStack {
            Group {
                if didSubmit {
                    successView
                } else {
                    feedbackForm
                }
            }
            .navigationTitle("Share feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if !didSubmit {
                    ToolbarItem(placement: .topBarTrailing) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Button("Send") {
                                Task { await submit() }
                            }
                            .fontWeight(.semibold)
                            .disabled(!canSubmit)
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private var feedbackForm: some View {
        Form {
            Section {
                Picker("Feedback type", selection: $category) {
                    ForEach(FeedbackCategory.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("What would you like to share?")
            }

            Section {
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            rating = value
                        } label: {
                            Image(systemName: value <= rating ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(value <= rating ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                        .accessibilityAddTraits(value == rating ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } header: {
                Text("How was your experience?")
            } footer: {
                if rating == 0 {
                    Text("Choose a rating before sending.")
                }
            }

            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 150)
                    .onChange(of: message) { _, newValue in
                        if newValue.count > maximumMessageLength {
                            message = String(newValue.prefix(maximumMessageLength))
                        }
                    }
                    .accessibilityLabel("Feedback message")

                HStack {
                    Text("Tell us what worked, what didn't, or what you'd like to see.")
                    Spacer()
                    Text("\(message.count)/\(maximumMessageLength)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Your feedback")
            }

            Section {
                Toggle("Include app and device details", isOn: $includeDiagnostics)
            } footer: {
                Text("Includes the app version, build number, device model, and iOS version. It never includes your sensor data or location.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var successView: some View {
        ContentUnavailableView {
            Label("Thank you!", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } description: {
            Text("Your feedback was sent to the Persephone's Basket team.")
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var canSubmit: Bool {
        rating > 0 && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !isSubmitting
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await APIClient.shared.submitFeedback(
                category: category,
                rating: rating,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                diagnostics: includeDiagnostics ? currentDiagnostics : nil
            )
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var currentDiagnostics: FeedbackDiagnostics {
        let info = Bundle.main.infoDictionary
        return FeedbackDiagnostics(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "Unknown",
            buildNumber: info?["CFBundleVersion"] as? String ?? "Unknown",
            osVersion: "iOS \(UIDevice.current.systemVersion)",
            deviceModel: UIDevice.current.model
        )
    }
}

#Preview {
    FeedbackView()
}
