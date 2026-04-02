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

            NewPostPlaceholderView()
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

private struct NewPostPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("New post form scaffold. Next: image picker + upload URL flow.")
                .padding()
                .navigationTitle("Create Post")
        }
    }
}

private struct ProfilePlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Profile/auth scaffold. Next: login + settings + notification toggle.")
                .padding()
                .navigationTitle("Profile")
        }
    }
}
