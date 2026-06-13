import Combine
import SwiftUI

@main
struct FarmConnectApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationManager.self) private var pushManager
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var feedViewModel = FeedViewModel()
    @StateObject private var assistantChatViewModel = AssistantChatViewModel()
    @StateObject private var sensorViewModel = SensorViewModel()

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
            .environmentObject(assistantChatViewModel)
            .environmentObject(sensorViewModel)
            .task {
                await sessionStore.restoreSessionIfPossible()
            }
            .onChange(of: sessionStore.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    pushManager.requestAuthorizationAndRegister()
                }
            }
            .onReceive(pushManager.$deviceToken.compactMap { $0 }) { token in
                guard sessionStore.isAuthenticated else { return }
                Task {
                    try? await APIClient.shared.registerDeviceToken(token)
                }
            }
        }
    }
}
