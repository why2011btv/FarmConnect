import SwiftUI

struct AccountMenuButton: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isNotificationSettingsOpen = false

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
        } label: {
            Image(systemName: "person.crop.circle")
        }
        .sheet(isPresented: $isNotificationSettingsOpen) {
            NotificationSettingsView()
        }
    }
}
