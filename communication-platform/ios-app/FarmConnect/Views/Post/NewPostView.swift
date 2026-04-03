import PhotosUI
import SwiftUI

struct NewPostView: View {
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @StateObject private var locationManager = UserLocationManager()

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var crop = "Corn"
    @State private var category: Category = .disease
    @State private var severity = 3
    @State private var visibility = "Public"
    @State private var imageUrl = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var uploadError: String?
    @State private var createError: String?

    private let cropOptions = ["Corn", "Wheat", "Apple", "Grape", "Vegetables", "Mixed", "Blueberries"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $descriptionText, axis: .vertical)
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
                    if visibility == "Private" {
                        Text("Private posts are not shown in the public feed tab.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Location") {
                    Button {
                        locationManager.requestCurrentLocation()
                    } label: {
                        Label("Use my current location", systemImage: "location.fill")
                    }
                    .buttonStyle(.bordered)

                    if locationManager.isLocating {
                        ProgressView("Getting location...")
                    }
                    if let city = locationManager.city {
                        Text("City: \(city)")
                    }
                    if let lat = locationManager.latitude, let lng = locationManager.longitude {
                        Text("Coordinates: \(lat.formatted(.number.precision(.fractionLength(4)))), \(lng.formatted(.number.precision(.fractionLength(4))))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let locationError = locationManager.locationError {
                        Text(locationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Media (optional)") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Photo", systemImage: "photo")
                    }
                    if isUploadingImage {
                        ProgressView("Uploading image...")
                    }
                    if let uploadError {
                        Text(uploadError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if !imageUrl.isEmpty {
                        Text("Uploaded: \(imageUrl)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Publish Post") {
                    Task {
                        createError = nil
                        guard
                            let lat = locationManager.latitude,
                            let lng = locationManager.longitude,
                            let city = locationManager.city
                        else {
                            createError = "Please grant location access and fetch your current location first."
                            return
                        }

                        await feedViewModel.createPost(
                            title: title.isEmpty ? "Untitled post" : title,
                            body: descriptionText.isEmpty ? "(no description)" : descriptionText,
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
                        descriptionText = ""
                        imageUrl = ""
                    }
                }
                .buttonStyle(.borderedProminent)

                if let createError {
                    Text(createError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Create Post")
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task {
                    await uploadSelectedPhoto(newValue)
                }
            }
            .task {
                locationManager.requestCurrentLocation()
            }
        }
    }

    private func uploadSelectedPhoto(_ item: PhotosPickerItem) async {
        isUploadingImage = true
        uploadError = nil
        defer { isUploadingImage = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                uploadError = "Failed to load selected image."
                return
            }
            let fileName = "post-\(UUID().uuidString).jpg"
            imageUrl = try await APIClient.shared.uploadImage(
                data: data,
                fileName: fileName,
                mimeType: "image/jpeg"
            )
        } catch {
            uploadError = "Image upload failed: \(error.localizedDescription)"
        }
    }
}
