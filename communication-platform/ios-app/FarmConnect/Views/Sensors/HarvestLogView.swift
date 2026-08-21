import Charts
import SwiftUI

@MainActor
final class HarvestLogViewModel: ObservableObject {
    @Published var samples: [FruitSample] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let farmId: String
    init(farmId: String) { self.farmId = farmId }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { samples = try await APIClient.shared.getFruitSamples(farmId: farmId) }
        catch { errorMessage = "Couldn't load samples." }
    }

    func add(sampledOn: String, block: String?, brix: Double?, ta: Double?, ph: Double?, notes: String?) async -> Bool {
        do {
            try await APIClient.shared.addFruitSample(farmId: farmId, sampledOn: sampledOn, blockLabel: block,
                                                       brix: brix, titratableAcidity: ta, ph: ph, notes: notes)
            await load()
            return true
        } catch { errorMessage = "Couldn't save the sample."; return false }
    }

    func delete(_ sample: FruitSample) async {
        do { try await APIClient.shared.deleteFruitSample(farmId: farmId, id: sample.id); await load() }
        catch { errorMessage = "Couldn't delete." }
    }
}

/// Log and trend fruit chemistry (Brix, titratable acidity, pH) toward harvest.
///
/// Harvest is a fruit-composition + tasting + rot-scouting decision — not something a temperature or
/// humidity sensor can make. This gives growers a place to record the numbers that actually drive
/// the pick, and to watch the trend. The incoming rain forecast is the deadline, not the sensors.
struct HarvestLogView: View {
    let farmId: String
    @StateObject private var model: HarvestLogViewModel
    @State private var showAdd = false

    init(farmId: String) {
        self.farmId = farmId
        _model = StateObject(wrappedValue: HarvestLogViewModel(farmId: farmId))
    }

    private var brixPoints: [(date: Date, brix: Double)] {
        model.samples.compactMap { s in
            guard let b = s.brix, let d = Self.parse(s.sampledOn) else { return nil }
            return (d, b)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Harvest is decided by fruit composition, tasting, and rot scouting — not by microclimate sensors. Log Brix, acidity, and pH over time and watch the trend; a rain forecast is your deadline to pick ahead of rot.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if brixPoints.count >= 2 {
                    Section("Brix trend") {
                        Chart(brixPoints, id: \.date) { p in
                            LineMark(x: .value("Date", p.date), y: .value("Brix", p.brix))
                            PointMark(x: .value("Date", p.date), y: .value("Brix", p.brix))
                        }
                        .frame(height: 160)
                    }
                }

                Section("Samples") {
                    if model.samples.isEmpty && !model.isLoading {
                        Text("No samples yet. Tap + to log your first Brix / TA / pH reading.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(model.samples.reversed()) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(s.sampledOn).font(.subheadline.weight(.semibold))
                                if let b = s.blockLabel, !b.isEmpty {
                                    Text(b).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(metricLine(s)).font(.footnote).monospacedDigit()
                            if let n = s.notes, !n.isEmpty {
                                Text(n).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { Task { await model.delete(s) } }
                        }
                    }
                }

                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Harvest log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await model.load() }
            .sheet(isPresented: $showAdd) { AddFruitSampleView(model: model) }
        }
    }

    private func metricLine(_ s: FruitSample) -> String {
        var parts: [String] = []
        if let b = s.brix { parts.append(String(format: "%.1f °Bx", b)) }
        if let t = s.titratableAcidity { parts.append(String(format: "TA %.1f g/L", t)) }
        if let p = s.ph { parts.append(String(format: "pH %.2f", p)) }
        return parts.isEmpty ? "—" : parts.joined(separator: "   ")
    }

    static func parse(_ iso: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: iso)
    }
}

private struct AddFruitSampleView: View {
    @ObservedObject var model: HarvestLogViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var block = ""
    @State private var brix = ""
    @State private var ta = ""
    @State private var ph = ""
    @State private var notes = ""

    private static let apiFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Sampled on", selection: $date, displayedComponents: .date)
                    TextField("Block (optional)", text: $block)
                }
                Section {
                    HStack { Text("Brix (°Bx)"); Spacer(); TextField("e.g. 22.5", text: $brix).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("TA (g/L)"); Spacer(); TextField("e.g. 6.5", text: $ta).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("pH"); Spacer(); TextField("e.g. 3.35", text: $ph).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                } header: {
                    Text("Measurements")
                } footer: {
                    Text("Typical targets — reds ~22–25 °Bx, TA ~6–8 g/L, pH 3.2–3.6; whites picked lower. Confirm with tasting and your winemaker.")
                }
                Section { TextField("Notes (taste, rot, weather)", text: $notes, axis: .vertical) }
            }
            .navigationTitle("New sample")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let ok = await model.add(
                                sampledOn: Self.apiFormatter.string(from: date),
                                block: block,
                                brix: Double(brix), ta: Double(ta), ph: Double(ph), notes: notes
                            )
                            if ok { dismiss() }
                        }
                    }
                    .disabled(brix.isEmpty && ta.isEmpty && ph.isEmpty)
                }
            }
        }
    }
}
