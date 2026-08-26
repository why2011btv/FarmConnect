import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var session: SessionStore
    @ObservedObject private var handoff = AssistantHandoff.shared
    @State private var selectedTab = 0
    @State private var showAddEmail = false
    @State private var skippedAddEmail = false

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

            // Staff only. The endpoints behind this answer 404 for everyone else, so hiding the
            // tab is presentation, not the access control itself.
            if session.isAdmin {
                AdminFarmsView()
                    .tag(3)
                    .tabItem {
                        Label("Admin", systemImage: "wrench.and.screwdriver")
                    }
            }
        }
        .sheet(isPresented: $showAddEmail) {
            AddEmailView()
                .environmentObject(session)
                .onDisappear { skippedAddEmail = true }
        }
        .task {
            // Prompt once per launch for accounts with no address on file.
            if session.needsEmail && !skippedAddEmail {
                showAddEmail = true
            }
        }
        .onChange(of: handoff.pendingPrompt) { _, prompt in
            if prompt != nil { selectedTab = 0 }
        }
    }
}
