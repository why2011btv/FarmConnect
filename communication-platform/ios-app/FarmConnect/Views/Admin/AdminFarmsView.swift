import SwiftUI

/// Staff home: every customer farm, and the button that onboards a new one.
struct AdminFarmsView: View {
    @StateObject private var model = AdminViewModel()
    @State private var showNewFarm = false

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }

                if model.farms.isEmpty && !model.isLoading {
                    Section {
                        Text("No customer farms yet. Tap + to provision one.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(model.farms) { farm in
                    NavigationLink(destination: AdminFarmDetailView(farmId: farm.id, farmName: farm.name)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(farm.name).font(.headline)
                            HStack(spacing: 10) {
                                Label("\(farm.onlineCount)/\(farm.deviceCount)", systemImage: "sensor.tag.radiowaves.forward")
                                Label("\(farm.memberCount)", systemImage: "person.2")
                                Label("\(farm.activeCodeCount)", systemImage: "key")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Customers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewFarm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await model.loadFarms() }
            .task { await model.loadFarms() }
            .sheet(isPresented: $showNewFarm) {
                AdminNewFarmView(model: model)
            }
            .overlay {
                if model.isLoading && model.farms.isEmpty {
                    ProgressView()
                }
            }
        }
    }
}

/// Provisioning form. On success it hands straight off to the one-time secrets screen.
struct AdminNewFarmView: View {
    @ObservedObject var model: AdminViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var nodeCount = 8
    @State private var provisioned: AdminProvisionResponse?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Farm or vineyard name", text: $name)
                        .textInputAutocapitalization(.words)
                    Stepper("Nodes: \(nodeCount)", value: $nodeCount, in: 1...64)
                }

                Section {
                    Button {
                        Task {
                            if let result = await model.createFarm(name: trimmedName, nodeCount: nodeCount) {
                                provisioned = result
                            }
                        }
                    } label: {
                        if model.isLoading {
                            ProgressView()
                        } else {
                            Text("Provision")
                        }
                    }
                    .disabled(trimmedName.isEmpty || model.isLoading)
                } footer: {
                    Text("Creates the farm, pre-registers \(nodeCount) nodes each with its own ingest key, and mints one access code. The code and keys are shown once.")
                }

                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("New customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $provisioned) { result in
                AdminSecretsView(
                    farmName: result.farm.name,
                    accessCode: result.accessCode,
                    nodes: result.nodes
                )
                .onDisappear { dismiss() }
            }
        }
    }
}

// Needed so the provisioning result can drive a `sheet(item:)`.
extension AdminProvisionResponse: Identifiable {
    var id: String { farm.id }
}
