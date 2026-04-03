import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tag(0)
                .tabItem {
                    Label("Feed", systemImage: "list.bullet.rectangle")
                }

            MapFeedView()
                .tag(1)
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            NewPostView()
                .tag(2)
                .tabItem {
                    Label("New", systemImage: "plus.circle")
                }

            ChatView()
                .tag(3)
                .tabItem {
                    Label("Chat", systemImage: "message")
                }

            SensorDashboardView()
                .tag(4)
                .tabItem {
                    Label("Sensors", systemImage: "waveform.path.ecg")
                }
        }
        .onChange(of: feedViewModel.refreshTrigger) { _, _ in
            selectedTab = 0
        }
    }
}
