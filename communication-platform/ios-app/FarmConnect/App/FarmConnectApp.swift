import SwiftUI

@main
struct FarmConnectApp: App {
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var feedViewModel = FeedViewModel()
    @StateObject private var chatViewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if sessionStore.isAuthenticated {
                    RootTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(sessionStore)
            .environmentObject(feedViewModel)
            .environmentObject(chatViewModel)
            .task {
                await sessionStore.restoreSessionIfPossible()
            }
        }
    }
}
