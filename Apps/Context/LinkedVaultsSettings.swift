import ContextVault
import Observation
import SwiftUI

/// Settings → Linked vaults: link Anytype spaces (and later Obsidian
/// folders) as sources. Context never writes its own files into them.
@MainActor
@Observable
final class LinkedVaultsModel {
    enum Step: Equatable {
        case idle
        case needsCode(challengeID: String)
        case pickSpace([AnytypeSpace])
    }

    var vaults: [LinkedVault] = []
    var status: [String: String] = [:]
    var step: Step = .idle
    var code = ""
    var pastedKey = ""
    var message: String?
    var busy = false

    private let registry = LinkedVaultRegistry.standard
    private let secrets: SecretStore = KeychainSecretStore()

    init() {
        reload()
    }

    func reload() {
        vaults = registry?.load() ?? []
        for vault in vaults { check(vault) }
    }

    func check(_ vault: LinkedVault) {
        guard let connector = Connectors.make(vault, secrets: secrets) else {
            status[vault.id] = "Not supported yet"
            return
        }
        status[vault.id] = "Checking…"
        Task {
            do {
                let count = try await connector.list().count
                status[vault.id] = "Connected · \(count) notes"
            } catch let error as VaultError {
                status[vault.id] = error.message
            } catch {
                status[vault.id] = "Couldn't reach this vault."
            }
        }
    }

    func unlink(_ vault: LinkedVault) {
        try? registry?.remove(id: vault.id)
        reload()
    }

    /// Starts Anytype linking. Reuses a saved key when it still works.
    func linkAnytype() {
        message = nil
        run {
            if let key = self.secrets.secret(for: Connectors.anytypeKeyAccount),
               let spaces = try? await AnytypeClient(apiKey: key).spaces()
            {
                self.step = .pickSpace(spaces)
                return
            }
            let challenge = try await AnytypeClient(apiKey: nil).startChallenge(appName: "Context")
            self.code = ""
            self.step = .needsCode(challengeID: challenge)
        }
    }

    func submitCode() {
        guard case .needsCode(let challenge) = step else { return }
        let code = code.trimmingCharacters(in: .whitespaces)
        run {
            let key = try await AnytypeClient(apiKey: nil).exchange(challengeID: challenge, code: code)
            try await self.useKey(key)
        }
    }

    func submitPastedKey() {
        let key = pastedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        run { try await self.useKey(key) }
    }

    private func useKey(_ key: String) async throws {
        let spaces = try await AnytypeClient(apiKey: key).spaces()
        try secrets.setSecret(key, for: Connectors.anytypeKeyAccount)
        pastedKey = ""
        step = .pickSpace(spaces)
    }

    func linkObsidian() {
        message = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose your Obsidian vault folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try registry?.linkObsidian(folder: url)
        } catch {
            message = "Couldn't save the linked vault."
        }
        reload()
    }

    func link(space: AnytypeSpace) {
        let vault = LinkedVault(kind: .anytype, name: space.name, spaceID: space.id)
        try? registry?.add(vault)
        step = .idle
        reload()
    }

    func cancel() {
        step = .idle
        message = nil
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await work()
            } catch let error as VaultError {
                message = error.message
            } catch {
                message = "Something went wrong talking to Anytype."
            }
        }
    }
}

struct LinkedVaultsSection: View {
    @State private var model = LinkedVaultsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Linked vaults")
                Spacer()
                Button("Link Obsidian…") { model.linkObsidian() }
                    .accessibilityIdentifier("settings.linked.obsidian")
                Button("Link Anytype…") { model.linkAnytype() }
                    .disabled(model.busy)
                    .accessibilityIdentifier("settings.linked.anytype")
            }
            if model.vaults.isEmpty {
                Text("None. Linked vaults are sources Context can read, edit, and attach to projects.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.vaults) { vault in
                HStack {
                    VStack(alignment: .leading) {
                        Text(vault.name)
                        Text("\(vault.kind == .anytype ? "Anytype" : "Obsidian") · \(model.status[vault.id] ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Unlink") { model.unlink(vault) }
                        .font(.caption)
                        .accessibilityIdentifier("settings.linked.unlink.\(vault.id)")
                }
            }
            switch model.step {
            case .idle:
                EmptyView()
            case .needsCode:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enter the 4-digit code Anytype is showing.")
                        .font(.caption)
                    HStack {
                        TextField("Code", text: $model.code)
                            .frame(width: 80)
                            .onSubmit { model.submitCode() }
                            .accessibilityIdentifier("settings.linked.anytype.code")
                        Button("Link") { model.submitCode() }.disabled(model.busy || model.code.count < 4)
                        Button("Cancel") { model.cancel() }
                    }
                    HStack {
                        SecureField("Or paste an API key from Anytype → Settings → API Keys", text: $model.pastedKey)
                            .onSubmit { model.submitPastedKey() }
                        Button("Use Key") { model.submitPastedKey() }.disabled(model.pastedKey.isEmpty)
                    }
                    .font(.caption)
                }
            case .pickSpace(let spaces):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a space to link.").font(.caption)
                    ForEach(spaces, id: \.id) { space in
                        Button(space.name) { model.link(space: space) }
                            .disabled(model.vaults.contains { $0.spaceID == space.id })
                    }
                    Button("Cancel") { model.cancel() }.font(.caption)
                }
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
