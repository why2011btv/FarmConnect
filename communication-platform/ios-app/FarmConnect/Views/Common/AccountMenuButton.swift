import SwiftUI

struct AccountMenuButton: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isNotificationSettingsOpen = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var showDeleteError = false

    var body: some View {
        Menu {
            if let user = session.currentUser {
                Text(user.name)
            }
            Button("Notification settings") {
                isNotificationSettingsOpen = true
            }
            Button("Sign out", role: .destructive) {
                session.logout()
            }
            Button("Delete account", role: .destructive) {
                isConfirmingDelete = true
            }
            .disabled(isDeleting)
        } label: {
            Image(systemName: "person.crop.circle")
        }
        .sheet(isPresented: $isNotificationSettingsOpen) {
            NotificationSettingsView()
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and removes your personal information. It can't be undone. Your past posts and messages remain but are no longer linked to you.")
        }
        .alert("Couldn't delete account", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "Please try again.")
        }
    }

    private func deleteAccount() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            let ok = await session.deleteAccount()
            isDeleting = false
            if !ok { showDeleteError = true }
            // On success the session is cleared and the app returns to the login screen automatically.
        }
    }
}
