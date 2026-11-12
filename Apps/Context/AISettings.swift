import ContextAI
import ContextDomain
import ContextVault
import SwiftUI

/// Where AI settings live: endpoint and model in settings.json, the key
/// in the Keychain.
enum AIConfig {
    static let keyAccount = "ai.apiKey"

    static var model: ModelConfig {
        let s = ContextSettings.shared
        let base = s.aiBaseURL.flatMap(URL.init(string:)) ?? ModelConfig.standard.baseURL
        let model = s.aiModel.flatMap { $0.isEmpty ? nil : $0 } ?? ModelConfig.defaultModel
        return ModelConfig(baseURL: base, model: model)
    }

    static var client: ModelClient {
        ModelClient(config: model, apiKey: KeychainSecretStore().secret(for: keyAccount))
    }
}

struct AISettingsRow: View {
    @State private var baseURL = AIConfig.model.baseURL.absoluteString
    @State private var model = AIConfig.model.model
    @State private var key = ""
    @State private var hasKey = KeychainSecretStore().secret(for: AIConfig.keyAccount) != nil
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI")
            TextField("Endpoint", text: $baseURL)
                .onSubmit(save)
                .accessibilityIdentifier("settings.ai.endpoint")
            TextField("Model", text: $model)
                .onSubmit(save)
                .accessibilityIdentifier("settings.ai.model")
            HStack {
                SecureField(hasKey ? "API key saved in Keychain" : "API key", text: $key)
                    .onSubmit(saveKey)
                    .accessibilityIdentifier("settings.ai.key")
                Button("Save") { save(); saveKey() }
            }
            HStack {
                Button("Use opencode's CXN key") { importOpencode() }
                    .accessibilityIdentifier("settings.ai.importOpencode")
                Button("Test") { test() }
                    .accessibilityIdentifier("settings.ai.test")
                Spacer()
            }
            .font(.caption)
            Text(status ?? "AI actions send the current note to \(AIConfig.model.hostLabel). Nothing is sent until you run one.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
        ContextSettings.shared.aiBaseURL = trimmedURL == ModelConfig.defaultBaseURL || trimmedURL.isEmpty ? nil : trimmedURL
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)
        ContextSettings.shared.aiModel = trimmedModel == ModelConfig.defaultModel || trimmedModel.isEmpty ? nil : trimmedModel
        ContextSettings.shared.save()
    }

    private func saveKey() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainSecretStore().setSecret(trimmed, for: AIConfig.keyAccount)
            key = ""
            hasKey = true
            status = "Key saved in the Keychain."
        } catch {
            status = "Couldn't save the key to the Keychain."
        }
    }

    private func importOpencode() {
        guard let provider = OpencodeConfig.provider(), let apiKey = provider.apiKey, !apiKey.isEmpty else {
            status = "No cxn-router key found in ~/.config/opencode/opencode.json."
            return
        }
        if let url = provider.baseURL { baseURL = url }
        save()
        key = apiKey
        saveKey()
        status = "Using opencode's CXN router endpoint and key."
    }

    private func test() {
        save()
        status = "Testing \(AIConfig.model.model)…"
        Task {
            do {
                _ = try await AIConfig.client.complete(system: "Reply with the single word: ok", user: "ping")
                status = "\(AIConfig.model.model) answered."
            } catch let error as ModelError {
                status = error.message
            } catch {
                status = "The test request failed."
            }
        }
    }
}
