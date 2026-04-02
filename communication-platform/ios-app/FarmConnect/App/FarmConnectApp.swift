import SwiftUI

@main
struct FarmConnectApp: App {
    @StateObject private var feedViewModel = FeedViewModel()
    @StateObject private var chatViewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(feedViewModel)
                .environmentObject(chatViewModel)
        }
    }
}
