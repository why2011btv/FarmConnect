import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "list.bullet.rectangle")
                }

            MapPlaceholderView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            NewPostView()
                .tabItem {
                    Label("New", systemImage: "plus.circle")
                }

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }

            ProfilePlaceholderView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}

private struct MapPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Map screen scaffold. Next: MapKit pins + post detail routing.")
                .padding()
                .navigationTitle("Map")
        }
    }
}

private struct ProfilePlaceholderView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let user = session.currentUser {
                    Text("Signed in as \(user.name)")
                } else {
                    Text("Not signed in")
                }
                Button("Sign out") {
                    session.logout()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Profile")
        }
    }
}
