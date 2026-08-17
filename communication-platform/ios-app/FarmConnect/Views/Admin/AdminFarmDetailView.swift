import SwiftUI

/// One customer: their nodes, who has access, and the codes that granted it.
struct AdminFarmDetailView: View {
    @StateObject private var model: AdminFarmDetailViewModel
    private let farmName: String

    @State private var issuedCode: String?
    @State private var rotatedNode: AdminProvisionedNode?
    @State private var confirmRevoke: AdminCode?
    @State private var confirmRemove: AdminMember?

    init(farmId: String, farmName: String) {
        _model = StateObject(wrappedValue: AdminFarmDetailViewModel(farmId: farmId))
        self.farmName = farmName
    }

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }

            Section("Nodes") {
                ForEach(model.detail?.devices ?? []) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle()
                                .fill(device.status == "online" ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(device.name).font(.headline)
                            Spacer()
                            if !device.hasIngestKey {
                                Text("no key")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(device.id)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Rotate key") {
                            Task {
                                if let result = await model.rotateKey(deviceId: device.id) {
                                    rotatedNode = AdminProvisionedNode(
                                        id: result.deviceId,
                                        name: device.name,
                                        locationLabel: device.locationLabel,
                                        ingestKey: result.ingestKey
                                    )
                                }
                            }
                        }
                        .tint(.orange)
                    }
                }
            }

            Section {
                ForEach(model.detail?.members ?? []) { member in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(member.name).font(.headline)
                            if member.role == "owner" {
                                Text("owner")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        if let email = member.email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { confirmRemove = member }
                    }
                }
            } header: {
                Text("People with access")
            } footer: {
                Text("Removing someone revokes their access immediately. Codes they used stay valid for everyone else.")
            }

            Section {
                ForEach(model.detail?.codes ?? []) { code in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(code.label ?? "Access code")
                                .font(.headline)
                                .strikethrough(!code.isActive)
                            Spacer()
                            Text(code.maxUses.map { "\(code.useCount)/\($0)" } ?? "\(code.useCount) uses")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !code.isActive {
                            Text("revoked").font(.caption2).foregroundStyle(.red)
                        }
                    }
                    .swipeActions {
                        if code.isActive {
                            Button("Revoke", role: .destructive) { confirmRevoke = code }
                        }
                    }
                }

                Button {
                    Task { issuedCode = await model.issueCode(label: "replacement card", maxUses: nil) }
                } label: {
                    Label("Issue another code", systemImage: "key.horizontal")
                }
            } header: {
                Text("Access codes")
            } footer: {
                // The plaintext is unrecoverable, so the list can only ever show metadata.
                Text("Only the hash of each code is stored, so existing codes can't be displayed again — issue a new one if a card is lost.")
            }
        }
        .navigationTitle(farmName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { await model.load() }
        .sheet(item: Binding(
            get: { issuedCode.map { IdentifiedString(value: $0) } },
            set: { issuedCode = $0?.value }
        )) { wrapper in
            AdminSecretsView(farmName: farmName, accessCode: wrapper.value, nodes: [])
        }
        .sheet(item: $rotatedNode) { node in
            AdminSecretsView(farmName: farmName, accessCode: nil, nodes: [node])
        }
        .alert("Revoke this code?", isPresented: Binding(
            get: { confirmRevoke != nil },
            set: { if !$0 { confirmRevoke = nil } }
        )) {
            Button("Revoke", role: .destructive) {
                if let code = confirmRevoke {
                    Task { await model.revokeCode(code.id) }
                }
                confirmRevoke = nil
            }
            Button("Cancel", role: .cancel) { confirmRevoke = nil }
        } message: {
            Text("Nobody new will be able to join with it. People who already joined keep their access.")
        }
        .alert("Remove this person?", isPresented: Binding(
            get: { confirmRemove != nil },
            set: { if !$0 { confirmRemove = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let member = confirmRemove {
                    Task { await model.removeMember(member.id) }
                }
                confirmRemove = nil
            }
            Button("Cancel", role: .cancel) { confirmRemove = nil }
        } message: {
            Text("They lose access to this farm's sensor data immediately.")
        }
    }
}

/// Lets a bare `String` drive `sheet(item:)`.
private struct IdentifiedString: Identifiable {
    let value: String
    var id: String { value }
}
