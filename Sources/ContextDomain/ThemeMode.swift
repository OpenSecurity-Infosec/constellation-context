import Foundation

/// Appearance preference: light, dark, or follow the system.
/// Lives in the domain layer so it is Codable-testable; AppKit applies it.
public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark

    /// Resolves the effective dark flag for a mode + system state.
    public func isDark(systemDark: Bool) -> Bool {
        switch self {
        case .system: return systemDark
        case .light: return false
        case .dark: return true
        }
    }
}
