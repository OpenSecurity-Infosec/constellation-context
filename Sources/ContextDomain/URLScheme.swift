import Foundation

/// `context://` URL scheme router. Lets Raycast/Alfred/scripts drive Context:
/// open, new note, search, and append. Domain-pure for unit tests; the app
/// delegate maps intents to window actions.
public enum URLScheme: Sendable {
    public static let scheme = "context"

    public enum Intent: Equatable, Sendable {
        case open
        case newNote(text: String?)
        case search(query: String)
        case append(text: String)
    }

    /// Parses `context://host?params` URLs into intents.
    /// Accepted forms:
    /// - `context://open` — show the overlay
    /// - `context://new?text=...` — create a note, optionally prefilled
    /// - `context://search?query=...` — open search with a query
    /// - `context://append?text=...` — append to the current note
    public static func parse(_ url: URL) -> Intent? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = (url.host ?? "").lowercased()
        // Support both `context://new?text=` and `context:new?text=` shapes.
        let pathAction = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let action = host.isEmpty ? pathAction : host
        let params = queryItems(url)
        switch action {
        case "", "open":
            return .open
        case "new", "create", "note":
            return .newNote(text: params["text"])
        case "search", "find":
            guard let q = params["query"] ?? params["q"] else { return nil }
            return .search(query: q)
        case "append":
            guard let t = params["text"] else { return nil }
            return .append(text: t)
        default:
            return nil
        }
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = parts.queryItems
        else { return [:] }
        var out: [String: String] = [:]
        for item in items {
            if let value = item.value { out[item.name.lowercased()] = value }
        }
        return out
    }
}
