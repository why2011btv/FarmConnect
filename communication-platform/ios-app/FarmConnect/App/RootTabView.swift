import SwiftUI

struct RootTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            AssistantChatView()
                .tag(0)
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }

            NotesView()
                .tag(1)
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }

            SensorDashboardView()
                .tag(2)
                .tabItem {
                    Label("Sensors", systemImage: "waveform.path.ecg")
                }
        }
    }
}
