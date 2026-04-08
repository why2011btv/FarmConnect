import SwiftUI

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = UserLocationManager()

    @State private var preferences = NotificationPreferences(
        enabled: true,
        radiusMiles: 10,
        categories: Category.allCases,
        quietHoursEnabled: false,
        quietStart: "22:00",
        quietEnd: "07:00",
        timezoneOffsetMinutes: 0,
        locationLat: nil,
        locationLng: nil
    )
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nearby alerts") {
                    Toggle("Enable nearby post notifications", isOn: $preferences.enabled)

                    if preferences.enabled {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Radius")
                                Spacer()
                                Text("\(preferences.radiusMiles) miles")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(preferences.radiusMiles) },
                                    set: { preferences.radiusMiles = Int($0.rounded()) }
                                ),
                                in: 1...100,
                                step: 1
                            )
                        }

                        Button {
                            locationManager.requestCurrentLocation()
                        } label: {
                            Label("Use current location", systemImage: "location.fill")
                        }
                        if locationManager.isLocating {
                            ProgressView("Locating...")
                        }
                        if let locationError = locationManager.locationError {
                            Text(locationError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Categories") {
                    ForEach(Category.allCases) { category in
                        Toggle(
                            category.rawValue,
                            isOn: Binding(
                                get: { preferences.categories.contains(category) },
                                set: { isSelected in
                                    if isSelected {
                                        if !preferences.categories.contains(category) {
                                            preferences.categories.append(category)
                                        }
                                    } else {
                                        preferences.categories.removeAll { $0 == category }
                                        if preferences.categories.isEmpty {
                                            preferences.categories = [category]
                                        }
                                    }
                                    preferences.categories.sort { $0.rawValue < $1.rawValue }
                                }
                            )
                        )
                    }
                }

                Section("Quiet hours") {
                    Toggle("Enable quiet hours", isOn: $preferences.quietHoursEnabled)

                    if preferences.quietHoursEnabled {
                        DatePicker(
                            "Start",
                            selection: Binding(
                                get: { dateFromHHMM(preferences.quietStart) },
                                set: { preferences.quietStart = hhmm(from: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        DatePicker(
                            "End",
                            selection: Binding(
                                get: { dateFromHHMM(preferences.quietEnd) },
                                set: { preferences.quietEnd = hhmm(from: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        Text("Quiet hours use your local timezone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Notification settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if didSave {
                    Text("Saved")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.green.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                }
            }
            .task {
                await load()
            }
            .onChange(of: locationManager.latitude) { _, _ in
                preferences.locationLat = locationManager.latitude
                preferences.locationLng = locationManager.longitude
            }
            .onChange(of: locationManager.longitude) { _, _ in
                preferences.locationLat = locationManager.latitude
                preferences.locationLng = locationManager.longitude
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            preferences = try await APIClient.shared.getNotificationPreferences()
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            var toSave = preferences
            toSave.timezoneOffsetMinutes = TimeZone.current.secondsFromGMT() / 60
            if toSave.categories.isEmpty {
                toSave.categories = Category.allCases
            }
            preferences = try await APIClient.shared.updateNotificationPreferences(toSave)
            withAnimation {
                didSave = true
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation {
                didSave = false
            }
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    private func dateFromHHMM(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2 else { return Date() }
        let hour = Int(parts[0]) ?? 0
        let minute = Int(parts[1]) ?? 0
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func hhmm(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }
}
