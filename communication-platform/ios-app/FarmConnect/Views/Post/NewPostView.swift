import PhotosUI
import SwiftUI

struct NewPostView: View {
    @EnvironmentObject private var feedViewModel: FeedViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = UserLocationManager()

    private let initialCategory: Category
    private let initialVisibility: String
    private let screenTitle: String
    private let publishButtonTitle: String
    private let successMessage: String

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var crop = ""
    @State private var category: Category
    @State private var severity = 3
    @State private var visibility: String
    @State private var imageUrl = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var uploadError: String?
    @State private var createError: String?
    @State private var showSuccessBanner = false

    private let cropSuggestions = ["Corn", "Wheat", "Apple", "Grape", "Vegetables", "Mixed", "Blueberries"]

    init(
        initialCategory: Category = .disease,
        initialVisibility: String = "Public",
        screenTitle: String = "Create Post",
        publishButtonTitle: String = "Publish Post",
        successMessage: String = "Post published"
    ) {
        self.initialCategory = initialCategory
        self.initialVisibility = initialVisibility
        self.screenTitle = screenTitle
        self.publishButtonTitle = publishButtonTitle
        self.successMessage = successMessage
        _category = State(initialValue: initialCategory)
        _visibility = State(initialValue: initialVisibility)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Tags") {
                    TextField("Crop (optional)", text: $crop)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(cropSuggestions, id: \.self) { value in
                                Button(value) {
                                    crop = value
                                }
                                .buttonStyle(.bordered)
                            }
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
                        Text("Photo uploaded")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }

                Button(publishButtonTitle) {
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

                        let didCreate = await feedViewModel.createPost(
                            title: title.isEmpty ? "Untitled post" : title,
                            body: descriptionText.isEmpty ? "(no description)" : descriptionText,
                            crop: normalizedCrop(),
                            category: category,
                            severity: severity,
                            visibility: visibility,
                            lat: lat,
                            lng: lng,
                            city: city,
                            imageUrl: imageUrl.isEmpty ? nil : imageUrl
                        )
                        guard didCreate else {
                            createError = feedViewModel.errorMessage ?? "Create post failed."
                            return
                        }
                        title = ""
                        descriptionText = ""
                        crop = ""
                        imageUrl = ""
                        await showSuccessThenDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)

                if let createError {
                    Text(createError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(screenTitle)
            .overlay(alignment: .top) {
                if showSuccessBanner {
                    Text(successMessage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.green.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task {
                    await uploadSelectedPhoto(newValue)
                }
            }
            .task {
                category = initialCategory
                visibility = initialVisibility
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

    private func normalizedCrop() -> String {
        let trimmed = crop.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private func showSuccessThenDismiss() async {
        withAnimation {
            showSuccessBanner = true
        }

        try? await Task.sleep(nanoseconds: 700_000_000)

        dismiss()
    }
}
