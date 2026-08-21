import SwiftUI

/// Per-block disease risk shown in the block detail. Uses THIS block's device readings (temperature,
/// humidity) fused with the weather API, so a humid low block and a breezy hilltop block get
/// different risk — the point of putting a sensor in each block.
struct BlockDiseaseRiskView: View {
    let latitude: Double
    let longitude: Double
    let deviceId: String?

    @StateObject private var model = DiseaseRiskViewModel()

    private var bloomDateString: String? {
        (UserDefaults.standard.object(forKey: "vineyard.bloomDate") as? Date).map {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: $0)
        }
    }

    var body: some View {
        List {
            if model.isLoading && model.assessment == nil {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            }
            if let error = model.errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            if let a = model.assessment {
                Section {
                    if a.phenology.inCriticalWindow {
                        Label("Critical window — protect on schedule", systemImage: "exclamationmark.shield.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                    }
                    Text(a.phenology.note).font(.caption).foregroundStyle(.secondary)
                    Text(provenanceNote(a)).font(.caption2).foregroundStyle(.secondary)
                } header: {
                    Text("This block")
                }

                ForEach(a.diseases) { d in
                    Section { DiseaseCard(disease: d) }
                }

                Section {
                    Text(a.disclaimer).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .task { await model.load(lat: latitude, lng: longitude, bloomDate: bloomDateString, deviceId: deviceId) }
        .refreshable { await model.load(lat: latitude, lng: longitude, bloomDate: bloomDateString, deviceId: deviceId) }
    }

    private func provenanceNote(_ a: DiseaseAssessment) -> String {
        guard let p = a.provenance, p.sensorHours > 0 else {
            return "Based on local weather for this block. Once this block's node has more history, its own readings refine the estimate."
        }
        return "Using \(p.sensorHours) h of this block's own sensor readings, with the weather API filling the rest."
    }
}
