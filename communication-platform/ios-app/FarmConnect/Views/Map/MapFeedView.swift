import MapKit
import SwiftUI
import CoreLocation

struct MapFeedView: View {
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @StateObject private var locationManager = UserLocationManager()
    @State private var selectedPost: Post?
    @State private var selectedCategory = "all"
    @State private var selectedTimeFilter: TimeFilter = .all
    @State private var nearbyOnly = true
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let nearbyRadiusMeters: CLLocationDistance = 30_000

    private var mapPosts: [Post] {
        guard let userLocation else { return posts }

        let ranked = posts.sorted {
            distance(from: userLocation, to: $0) < distance(from: userLocation, to: $1)
        }
        guard nearbyOnly else { return ranked }
        return ranked.filter { distance(from: userLocation, to: $0) <= nearbyRadiusMeters }
    }

    private var userLocation: CLLocation? {
        guard
            let lat = locationManager.latitude,
            let lng = locationManager.longitude
        else {
            return nil
        }
        return CLLocation(latitude: lat, longitude: lng)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All types").tag("all")
                        Text("Disease").tag("Disease")
                        Text("Pest").tag("Pest")
                        Text("Weather").tag("Weather")
                        Text("Note").tag("Note")
                        Text("Market").tag("Market")
                    }
                    .pickerStyle(.menu)

                    Picker("Time", selection: $selectedTimeFilter) {
                        ForEach(TimeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)

                Toggle(isOn: $nearbyOnly) {
                    Text("Nearby only")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal)

                if nearbyOnly, mapPosts.isEmpty, !isLoading {
                    Text("No nearby posts in the current filters. Turn off Nearby only to see all filtered posts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let locationError = locationManager.locationError {
                    Text(locationError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Map(position: $mapPosition) {
                    UserAnnotation()
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
                .overlay(alignment: .topTrailing) {
                    if isLoading {
                        ProgressView()
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding()
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
            }
            .navigationTitle("Map")
            .onChange(of: selectedCategory) { _, _ in
                Task { await loadPosts() }
            }
            .onChange(of: selectedTimeFilter) { _, _ in
                Task { await loadPosts() }
            }
            .onChange(of: locationManager.latitude) { _, _ in
                centerOnUserIfAvailable()
            }
            .onChange(of: locationManager.longitude) { _, _ in
                centerOnUserIfAvailable()
            }
            .task {
                locationManager.requestCurrentLocation()
                await loadPosts()
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

    private func loadPosts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await APIClient.shared.getPosts(
                query: "",
                category: selectedCategory,
                timeFilter: selectedTimeFilter
            )
            posts = fetched
            feedViewModel.posts = fetched
        } catch {
            errorMessage = "Failed to load map posts: \(error.localizedDescription)"
        }
    }

    private func centerOnUserIfAvailable() {
        guard let userLocation else { return }
        mapPosition = .region(
            MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            )
        )
    }

    private func distance(from user: CLLocation, to post: Post) -> CLLocationDistance {
        let postLocation = CLLocation(latitude: post.lat, longitude: post.lng)
        return user.distance(from: postLocation)
    }
}
