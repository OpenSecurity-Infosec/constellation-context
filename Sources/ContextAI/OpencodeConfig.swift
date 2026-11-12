import Foundation

/// Reads the CXN router provider from a local opencode config so the
/// user can reuse its endpoint and key with one click. Read-only.
public enum OpencodeConfig {
    public struct Provider: Equatable, Sendable {
        public var baseURL: String?
        public var apiKey: String?
    }

    public static var standardFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode/opencode.json")
    }

    public static func provider(named name: String = "cxn-router", in file: URL = standardFile) -> Provider? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = (json["providers"] ?? json["provider"]) as? [String: Any],
              let provider = providers[name] as? [String: Any]
        else { return nil }
        let settings = (provider["settings"] ?? provider["options"]) as? [String: Any] ?? [:]
        return Provider(baseURL: settings["baseURL"] as? String, apiKey: settings["apiKey"] as? String)
    }
}
