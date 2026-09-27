import ContextDomain
import Foundation

/// MVP settings. Persisted as JSON in Application Support.
public struct ContextSettings: Codable, Sendable {
    public var fontSize: CGFloat = 14
    public var showMenuBarExtra: Bool = true
    public var pinOnTop: Bool = false
    public var hotKeyCode: UInt32 = 0 // ANSI A
    public var hotKeyModifiers: UInt32 = 0x0800 // optionKey
    public var obsidianVaultPath: String? = nil
    public var themeMode: ThemeMode = .system
    public var iCloudSyncEnabled: Bool = false
    public var lastSyncAt: Date? = nil
    public var extensionsAllowNetwork: Bool = false

    public nonisolated(unsafe) static var shared = ContextSettings.load()

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ConstellationContext", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("settings.json")
    }

    public static func load() -> ContextSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(ContextSettings.self, from: data)
        else { return ContextSettings(fontSize: 14, showMenuBarExtra: true, pinOnTop: false, hotKeyCode: 0, hotKeyModifiers: 0x0800) }
        return decoded
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
