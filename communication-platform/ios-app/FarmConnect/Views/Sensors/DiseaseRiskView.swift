import SwiftUI

@MainActor
final class DiseaseRiskViewModel: ObservableObject {
    @Published var assessment: DiseaseAssessment?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(lat: Double, lng: Double, bloomDate: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            assessment = try await APIClient.shared.getDiseaseRisk(lat: lat, lng: lng, bloomDate: bloomDate, shootCm: nil)
        } catch {
            errorMessage = (error as? APIError).flatMap {
                if case .serverMessage(_, let m) = $0 { return m } else { return nil }
            } ?? "Couldn't load disease risk. Try again."
        }
    }
}

/// Validated, weather-driven disease infection-condition estimates for the vineyard.
///
/// This is the authoritative disease view (replacing the earlier invented indices). It is scouting
/// decision support, not a spray recommendation — the server disclaimer is shown and non-removable.
struct DiseaseRiskView: View {
    let latitude: Double
    let longitude: Double

    @StateObject private var model = DiseaseRiskViewModel()
    @State private var bloomDate: Date?
    @State private var showBloomPicker = false

    private static let bloomKey = "vineyard.bloomDate"
    private static let apiFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private var bloomDateString: String? {
        bloomDate.map { Self.apiFormatter.string(from: $0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if model.isLoading && model.assessment == nil {
                    Section { HStack { Spacer(); ProgressView(); Spacer() } }
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                if let a = model.assessment {
                    phenologySection(a)
                    diseaseSection(a)
                    contextSection(a)
                    Section {
                        Text(a.disclaimer)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Section("Sources & pesticide safety") {
                        if let url = URL(string: "https://newa.cornell.edu/grape-diseases") {
                            Link("Cornell NEWA grape disease models", destination: url)
                                .font(.footnote)
                        }
                        if let url = URL(string: "https://cropandpestguides.cce.cornell.edu") {
                            Link("NY & PA Pest Management Guidelines for Grapes", destination: url)
                                .font(.footnote)
                        }
                        Text("The product label is the legal authority on materials, rate, REI and PHI. Consult it and a licensed advisor before any application.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Disease risk")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if bloomDate == nil { bloomDate = UserDefaults.standard.object(forKey: Self.bloomKey) as? Date }
                await reload()
            }
            .refreshable { await reload() }
            .sheet(isPresented: $showBloomPicker) { bloomPicker }
        }
    }

    private func reload() async {
        await model.load(lat: latitude, lng: longitude, bloomDate: bloomDateString)
    }

    // MARK: - Sections

    @ViewBuilder
    private func phenologySection(_ a: DiseaseAssessment) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if a.phenology.inCriticalWindow {
                    Label("Critical window — protect on schedule", systemImage: "exclamationmark.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text(a.phenology.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showBloomPicker = true
                } label: {
                    Label(a.phenology.hasBloomDate ? "Change bloom date" : "Set your bloom date", systemImage: "calendar")
                        .font(.footnote)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Vineyard stage")
        }
    }

    @ViewBuilder
    private func diseaseSection(_ a: DiseaseAssessment) -> some View {
        Section("Infection conditions") {
            ForEach(a.diseases) { d in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(d.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(levelLabel(d.level))
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(levelColor(d.level).opacity(0.2), in: Capsule())
                            .foregroundStyle(levelColor(d.level))
                    }
                    Text(d.headline).font(.footnote)
                    Text(d.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func contextSection(_ a: DiseaseAssessment) -> some View {
        Section("Season context") {
            HStack {
                Text("Growing degree days (base 50°F, since Apr 1)")
                    .font(.footnote)
                Spacer()
                Text("\(a.gddBase50FromApr1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private var bloomPicker: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Bloom date",
                        selection: Binding(get: { bloomDate ?? Date() }, set: { bloomDate = $0 }),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                } footer: {
                    Text("When about 50% of your vines reached full bloom. Anchors the disease critical window and stage-based timing.")
                }
            }
            .navigationTitle("Bloom date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let d = bloomDate { UserDefaults.standard.set(d, forKey: Self.bloomKey) }
                        showBloomPicker = false
                        Task { await reload() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if bloomDate == nil { bloomDate = UserDefaults.standard.object(forKey: Self.bloomKey) as? Date }
        }
    }

    // MARK: - Styling

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "high": return .red
        case "moderate": return .orange
        case "low": return .green
        default: return .secondary
        }
    }

    private func levelLabel(_ level: String) -> String {
        switch level {
        case "high": return "HIGH"
        case "moderate": return "MODERATE"
        case "low": return "LOW"
        default: return "N/A"
        }
    }
}
