import Foundation

/// Named color themes beyond system/light/dark. Each theme carries a light
/// and dark paper tone plus an accent, applied instantly with no restart.
/// The editor text size already lives in settings; translucency is separate.
public enum ColorTheme: String, Codable, Sendable, CaseIterable {
    case mocha
    case paper
    case forest

    public var displayName: String {
        switch self {
        case .mocha: return "Mocha"
        case .paper: return "Paper"
        case .forest: return "Forest"
        }
    }

    /// Hex triplets: light editor bg, dark editor bg, accent.
    public var palette: (light: String, dark: String, accent: String) {
        switch self {
        case .mocha:
            return ("EFF1F5", "1E1E2E", "B4BEFE")
        case .paper:
            return ("F4F2EC", "1F1D1A", "B57614")
        case .forest:
            return ("EFF5EF", "1A2B22", "7FBC8A")
        }
    }

    /// Text color (light, dark), when the theme sets its own ink. Nil means
    /// the system label color.
    public var ink: (light: String, dark: String)? {
        switch self {
        case .paper: return ("2B2925", "E9E4D8")
        case .mocha, .forest: return nil
        }
    }
}
