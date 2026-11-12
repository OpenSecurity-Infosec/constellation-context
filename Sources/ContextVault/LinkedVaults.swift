import Foundation
import Security

/// One linked vault as configured by the user. Secrets are not stored
/// here; they live in a `SecretStore` keyed by `id`.
public struct LinkedVault: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: VaultKind
    public var name: String
    /// Folder for Obsidian vaults.
    public var path: String?
    /// Space for Anytype vaults.
    public var spaceID: String?

    public init(id: String = UUID().uuidString, kind: VaultKind, name: String, path: String? = nil, spaceID: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.path = path
        self.spaceID = spaceID
    }
}

/// The list of linked vaults, saved as JSON beside the app settings.
public struct LinkedVaultRegistry: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/ConstellationContext/vaults.json`.
    public static var standard: LinkedVaultRegistry? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first.map {
            LinkedVaultRegistry(fileURL: $0.appendingPathComponent("ConstellationContext/vaults.json"))
        }
    }

    public func load() -> [LinkedVault] {
        guard let data = try? Data(contentsOf: fileURL),
              let vaults = try? JSONDecoder().decode([LinkedVault].self, from: data)
        else { return [] }
        return vaults
    }

    public func save(_ vaults: [LinkedVault]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(vaults).write(to: fileURL, options: .atomic)
    }

    public func add(_ vault: LinkedVault) throws {
        var all = load().filter { $0.id != vault.id }
        all.append(vault)
        try save(all)
    }

    /// The first linked Obsidian vault's folder, if any.
    public var obsidianFolder: URL? {
        load().first { $0.kind == .obsidian }?.path.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Links `folder` as an Obsidian vault unless it is already linked.
    @discardableResult
    public func linkObsidian(folder: URL) throws -> LinkedVault {
        let path = folder.standardizedFileURL.path
        if let existing = load().first(where: { $0.kind == .obsidian && $0.path == path }) { return existing }
        let vault = LinkedVault(kind: .obsidian, name: folder.lastPathComponent, path: path)
        try add(vault)
        return vault
    }

    public func remove(id: String) throws {
        try save(load().filter { $0.id != id })
    }
}

/// Where API keys and tokens live. Production uses the Keychain; tests
/// use `MemorySecretStore` so they never touch the user's keychain.
public protocol SecretStore: Sendable {
    func secret(for account: String) -> String?
    func setSecret(_ value: String?, for account: String) throws
}

public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "app.constellation.Context") {
        self.service = service
    }

    public func secret(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ value: String?, for account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.unavailable("Could not save to the Keychain (\(status)).")
        }
    }
}

public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public func secret(for account: String) -> String? {
        lock.withLock { values[account] }
    }

    public func setSecret(_ value: String?, for account: String) throws {
        lock.withLock { values[account] = value }
    }
}

/// Builds the connector for a linked vault.
public enum Connectors {
    /// One Anytype API key serves every space in the user's account.
    public static let anytypeKeyAccount = "anytype.apiKey"

    public static func make(
        _ vault: LinkedVault,
        secrets: SecretStore,
        anytypeTransport: AnytypeTransport = URLSessionAnytypeTransport()
    ) -> (any VaultConnector)? {
        switch vault.kind {
        case .anytype:
            guard let space = vault.spaceID else { return nil }
            return AnytypeConnector(
                id: vault.id, displayName: vault.name, spaceID: space,
                client: AnytypeClient(transport: anytypeTransport, apiKey: secrets.secret(for: anytypeKeyAccount))
            )
        case .obsidian:
            guard let path = vault.path else { return nil }
            return ObsidianConnector(id: vault.id, displayName: vault.name, root: URL(fileURLWithPath: path, isDirectory: true))
        }
    }
}
