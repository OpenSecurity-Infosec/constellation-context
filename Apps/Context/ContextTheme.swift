import AppKit
import ContextDomain
import SwiftUI

/// Catppuccin Mocha tokens. Dark default is Mocha; light uses Latte.
/// System chrome stays ~85%; these colors carry editor surfaces and accents.
enum ContextTheme {
    // Mocha
    static let mochaBase = NSColor(srgbRed: 0x1e / 255, green: 0x1e / 255, blue: 0x2e / 255, alpha: 1)
    static let mochaMantle = NSColor(srgbRed: 0x18 / 255, green: 0x18 / 255, blue: 0x25 / 255, alpha: 1)
    static let mochaCrust = NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x1b / 255, alpha: 1)
    static let mochaText = NSColor(srgbRed: 0xcd / 255, green: 0xd6 / 255, blue: 0xf4 / 255, alpha: 1)
    static let mochaSubtext = NSColor(srgbRed: 0xa6 / 255, green: 0xad / 255, blue: 0xc8 / 255, alpha: 1)
    static let mochaOverlay = NSColor(srgbRed: 0x6c / 255, green: 0x70 / 255, blue: 0x8c / 255, alpha: 1)
    static let mochaBlue = NSColor(srgbRed: 0x89 / 255, green: 0xb4 / 255, blue: 0xfa / 255, alpha: 1)
    static let mochaLavender = NSColor(srgbRed: 0xb4 / 255, green: 0xbe / 255, blue: 0xfe / 255, alpha: 1)
    static let mochaGreen = NSColor(srgbRed: 0xa6 / 255, green: 0xe3 / 255, blue: 0xa1 / 255, alpha: 1)
    static let mochaPeach = NSColor(srgbRed: 0xfa / 255, green: 0xb3 / 255, blue: 0x87 / 255, alpha: 1)
    static let mochaRed = NSColor(srgbRed: 0xf3 / 255, green: 0x8b / 255, blue: 0x8d / 255, alpha: 1)

    /// Resolves the effective dark/light appearance for a theme mode.
    static func isDark(mode: ThemeMode, systemDark: Bool) -> Bool {
        mode.isDark(systemDark: systemDark)
    }

    /// Applies the mode to every Context window. No restart needed.
    @MainActor
    static func apply(mode: ThemeMode) {
        let name: NSAppearance.Name? = switch mode {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
        for window in NSApp.windows {
            window.appearance = name.flatMap { NSAppearance(named: $0) }
        }
    }

    static var editorBackground: NSColor {
        NSColor(name: "ContextEditorBackground") { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil { return mochaBase }
            return NSColor(srgbRed: 0xeff / 255, green: 0xf1 / 255, blue: 0xf5 / 255, alpha: 1)
        }
    }

    static var panelBackground: NSColor {
        NSColor(name: "ContextPanelBackground") { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil { return mochaMantle }
            return NSColor(srgbRed: 0xe6 / 255, green: 0xe9 / 255, blue: 0xef / 255, alpha: 1)
        }
    }

    static var accent: NSColor {
        NSColor(name: "ContextAccent") { appearance in
            if appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil { return mochaLavender }
            return NSColor(srgbRed: 0x74 / 255, green: 0x87 / 255, blue: 0xfa / 255, alpha: 1)
        }
    }

    static var bodyFont: NSFont { .systemFont(ofSize: ContextSettings.shared.fontSize) }
    static var monoFont: NSFont {
        .monospacedSystemFont(ofSize: ContextSettings.shared.fontSize, weight: .regular)
    }
}

extension Color {
    static var ctxEditorBackground: Color { Color(nsColor: ContextTheme.editorBackground) }
    static var ctxPanelBackground: Color { Color(nsColor: ContextTheme.panelBackground) }
    static var ctxAccent: Color { Color(nsColor: ContextTheme.accent) }
}
