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
    /// Base vault folder; nil means `~/Context` (ADR-0002).
    public var baseVaultPath: String? = nil
    /// Keep copies as editable notes in the Clipboard pad.
    public var clipboardHistory: Bool = true
    /// OpenAI-compatible endpoint and model for AI actions; nil = defaults.
    public var aiBaseURL: String? = nil
    public var aiModel: String? = nil
    public var extensionsAllowNetwork: Bool = false
    public var showInDock: Bool = true
    public var colorTheme: ColorTheme = .paper
    public var translucentWindow: Bool = false
    public var lastExportDirectory: String? = nil

    public nonisolated(unsafe) static var shared = ContextSettings.load()

    public init(
        fontSize: CGFloat = 14,
        showMenuBarExtra: Bool = true,
        pinOnTop: Bool = false,
        hotKeyCode: UInt32 = 0,
        hotKeyModifiers: UInt32 = 0x0800,
        obsidianVaultPath: String? = nil,
        themeMode: ThemeMode = .system,
        baseVaultPath: String? = nil,
        extensionsAllowNetwork: Bool = false,
        showInDock: Bool = true,
        colorTheme: ColorTheme = .paper,
        translucentWindow: Bool = false,
        lastExportDirectory: String? = nil
    ) {
        self.fontSize = fontSize
        self.showMenuBarExtra = showMenuBarExtra
        self.pinOnTop = pinOnTop
        self.hotKeyCode = hotKeyCode
        self.hotKeyModifiers = hotKeyModifiers
        self.obsidianVaultPath = obsidianVaultPath
        self.themeMode = themeMode
        self.baseVaultPath = baseVaultPath
        self.extensionsAllowNetwork = extensionsAllowNetwork
        self.showInDock = showInDock
        self.colorTheme = colorTheme
        self.translucentWindow = translucentWindow
        self.lastExportDirectory = lastExportDirectory
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
        case obsidianVaultPath, themeMode, baseVaultPath, clipboardHistory, aiBaseURL, aiModel
        case extensionsAllowNetwork, showInDock, colorTheme, translucentWindow
        case lastExportDirectory
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
        baseVaultPath = try c.decodeIfPresent(String.self, forKey: .baseVaultPath)
        clipboardHistory = try c.decodeIfPresent(Bool.self, forKey: .clipboardHistory) ?? true
        aiBaseURL = try c.decodeIfPresent(String.self, forKey: .aiBaseURL)
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel)
        extensionsAllowNetwork = try c.decodeIfPresent(Bool.self, forKey: .extensionsAllowNetwork) ?? false
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? true
        colorTheme = try c.decodeIfPresent(ColorTheme.self, forKey: .colorTheme) ?? .paper
        translucentWindow = try c.decodeIfPresent(Bool.self, forKey: .translucentWindow) ?? false
        lastExportDirectory = try c.decodeIfPresent(String.self, forKey: .lastExportDirectory)
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
