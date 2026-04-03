import MapKit
import SwiftUI

struct MapFeedView: View {
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @State private var selectedPost: Post?

    private var mapPosts: [Post] {
        feedViewModel.posts.filter { $0.visibility == "Public" }
    }

    var body: some View {
        NavigationStack {
            Map {
                ForEach(mapPosts) { post in
                    Annotation(post.title, coordinate: CLLocationCoordinate2D(latitude: post.lat, longitude: post.lng)) {
                        Button {
                            selectedPost = post
                        } label: {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                                .background(.white, in: Circle())
                        }
                    }
                }
            }
            .navigationTitle("Map")
            .task {
                await feedViewModel.load()
            }
            .sheet(item: $selectedPost) { post in
                NavigationStack {
                    PostDetailView(post: post)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { selectedPost = nil }
                            }
                        }
                }
            }
        }
    }
}
