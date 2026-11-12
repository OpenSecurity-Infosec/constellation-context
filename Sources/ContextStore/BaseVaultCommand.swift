import ContextVault

public enum BaseVaultCommand: Sendable {
    case write(VaultNote)
}

extension Workspace {
    public static let baseSourceID = "context.base"

    public var baseConnector: any VaultConnector {
        ObsidianConnector(id: Self.baseSourceID, displayName: "Base Vault", root: vault.root)
    }

    /// Arbitrary base-vault documents share the connector's conflict and lossless checks.
    public func apply(_ command: BaseVaultCommand) async throws -> VaultNote {
        switch command {
        case .write(let note):
            let written = try await baseConnector.write(note)
            for pad in pads { _ = store(for: pad).reloadFromDisk() }
            return written
        }
    }
}
