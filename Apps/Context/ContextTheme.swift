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

    /// Applies the named color theme + translucency to the overlay window.
    @MainActor
    static func applyLook(theme: ColorTheme, translucent: Bool, to window: NSWindow?) {
        guard let window else { return }
        if translucent {
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.titlebarAppearsTransparent = true
            // Frosted blur behind the editor chrome.
            if window.contentView?.subviews.first(where: { $0 is NSVisualEffectView }) == nil {
                let blur = NSVisualEffectView(frame: window.contentLayoutRect)
                blur.autoresizingMask = [.width, .height]
                blur.material = .sidebar
                blur.blendingMode = .behindWindow
                blur.state = .active
                window.contentView?.addSubview(blur, positioned: .below, relativeTo: nil)
            }
        } else {
            window.isOpaque = true
            window.backgroundColor = nil
            window.titlebarAppearsTransparent = false
            for sub in window.contentView?.subviews ?? [] where sub is NSVisualEffectView {
                sub.removeFromSuperview()
            }
        }
        _ = theme
    }

    static func hex(_ s: String) -> NSColor {
        var h = s.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 {
            h = h.map { "\($0)\($0)" }.joined()
        }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return .clear }
        return NSColor(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    static var editorBackground: NSColor {
        let theme = ContextSettings.shared.colorTheme
        return NSColor(name: "ContextEditorBackground") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            let hex = dark ? theme.palette.dark : theme.palette.light
            return ContextTheme.hex(hex)
        }
    }

    static var panelBackground: NSColor {
        let theme = ContextSettings.shared.colorTheme
        return NSColor(name: "ContextPanelBackground") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            // Panel is a half-step toward the opposite pole for separation.
            if theme == .mocha {
                if dark { return mochaMantle }
                return NSColor(srgbRed: 0xe6 / 255, green: 0xe9 / 255, blue: 0xef / 255, alpha: 1)
            }
            let hex = dark ? theme.palette.dark : theme.palette.light
            return ContextTheme.hex(hex).blended(withFraction: 0.12, of: .secondaryLabelColor) ?? ContextTheme.hex(hex)
        }
    }

    static var accent: NSColor {
        let theme = ContextSettings.shared.colorTheme
        return NSColor(name: "ContextAccent") { _ in ContextTheme.hex(theme.palette.accent) }
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
