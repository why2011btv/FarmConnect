import SwiftUI

struct NewPostView: View {
    @EnvironmentObject private var feedViewModel: FeedViewModel

    @State private var title = ""
    @State private var body = ""
    @State private var crop = "Corn"
    @State private var category: Category = .disease
    @State private var severity = 3
    @State private var visibility = "Public"
    @State private var city = "Miami"
    @State private var lat = 25.7742
    @State private var lng = -80.1936
    @State private var imageUrl = ""

    private let cropOptions = ["Corn", "Wheat", "Apple", "Grape", "Vegetables", "Mixed", "Blueberries"]
    private let cityOptions = ["Montpelier", "Boston", "Miami", "New York", "Los Angeles", "Chicago"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $body, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Tags") {
                    Picker("Crop", selection: $crop) {
                        ForEach(cropOptions, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    Picker("Severity", selection: $severity) {
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag("Public")
                        Text("Private").tag("Private")
                    }
                }

                Section("Location") {
                    Picker("City", selection: $city) {
                        ForEach(cityOptions, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    TextField("Latitude", value: $lat, format: .number)
                    TextField("Longitude", value: $lng, format: .number)
                }

                Section("Media (optional)") {
                    TextField("Image URL (or upload result URL)", text: $imageUrl)
                    Text("Next step: use PhotosPicker + upload URL endpoint to upload binary image and auto-fill public URL.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Publish Post") {
                    Task {
                        await feedViewModel.createPost(
                            title: title.isEmpty ? "Untitled post" : title,
                            body: body.isEmpty ? "(no description)" : body,
                            crop: crop,
                            category: category,
                            severity: severity,
                            visibility: visibility,
                            lat: lat,
                            lng: lng,
                            city: city,
                            imageUrl: imageUrl.isEmpty ? nil : imageUrl
                        )
                        title = ""
                        body = ""
                        imageUrl = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Create Post")
        }
    }
}
