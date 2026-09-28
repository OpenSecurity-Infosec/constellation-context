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
            return ("FAF6EE", "2A2620", "B57614")
        case .forest:
            return ("EFF5EF", "1A2B22", "7FBC8A")
        }
    }
}
