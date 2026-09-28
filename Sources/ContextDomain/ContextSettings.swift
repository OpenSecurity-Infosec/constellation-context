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
    public var showInDock: Bool = true
    public var colorTheme: ColorTheme = .mocha
    public var translucentWindow: Bool = false

    public nonisolated(unsafe) static var shared = ContextSettings.load()

    public init(
        fontSize: CGFloat = 14,
        showMenuBarExtra: Bool = true,
        pinOnTop: Bool = false,
        hotKeyCode: UInt32 = 0,
        hotKeyModifiers: UInt32 = 0x0800,
        obsidianVaultPath: String? = nil,
        themeMode: ThemeMode = .system,
        iCloudSyncEnabled: Bool = false,
        lastSyncAt: Date? = nil,
        extensionsAllowNetwork: Bool = false,
        showInDock: Bool = true,
        colorTheme: ColorTheme = .mocha,
        translucentWindow: Bool = false
    ) {
        self.fontSize = fontSize
        self.showMenuBarExtra = showMenuBarExtra
        self.pinOnTop = pinOnTop
        self.hotKeyCode = hotKeyCode
        self.hotKeyModifiers = hotKeyModifiers
        self.obsidianVaultPath = obsidianVaultPath
        self.themeMode = themeMode
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.lastSyncAt = lastSyncAt
        self.extensionsAllowNetwork = extensionsAllowNetwork
        self.showInDock = showInDock
        self.colorTheme = colorTheme
        self.translucentWindow = translucentWindow
    }

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

    // MARK: - Tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case fontSize, showMenuBarExtra, pinOnTop, hotKeyCode, hotKeyModifiers
        case obsidianVaultPath, themeMode, iCloudSyncEnabled, lastSyncAt
        case extensionsAllowNetwork, showInDock, colorTheme, translucentWindow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 14
        showMenuBarExtra = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarExtra) ?? true
        pinOnTop = try c.decodeIfPresent(Bool.self, forKey: .pinOnTop) ?? false
        hotKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .hotKeyCode) ?? 0
        hotKeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers) ?? 0x0800
        obsidianVaultPath = try c.decodeIfPresent(String.self, forKey: .obsidianVaultPath)
        themeMode = try c.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .system
        iCloudSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? false
        lastSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        extensionsAllowNetwork = try c.decodeIfPresent(Bool.self, forKey: .extensionsAllowNetwork) ?? false
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? true
        colorTheme = try c.decodeIfPresent(ColorTheme.self, forKey: .colorTheme) ?? .mocha
        translucentWindow = try c.decodeIfPresent(Bool.self, forKey: .translucentWindow) ?? false
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
