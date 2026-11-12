import Foundation

/// `context://` URL scheme router. Lets Raycast/Alfred/scripts drive Context:
/// open, new note, search, and append. Domain-pure for unit tests; the app
/// delegate maps intents to window actions.
public enum URLScheme: Sendable {
    public static let scheme = "context"

    public enum Intent: Equatable, Sendable {
        case open
        case openNote(id: UUID)
        case appendToNote(id: UUID, text: String)
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
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil,
              host.isEmpty || url.path.isEmpty || url.path == "/" else { return nil }
        let items = components.queryItems ?? []
        let names = items.map { $0.name.lowercased() }
        guard Set(names).count == names.count,
              names.allSatisfy({ ["text", "query", "q", "id"].contains($0) }),
              items.allSatisfy({ $0.value != nil }),
              (components.percentEncodedQuery?.removingPercentEncoding != nil || items.isEmpty) else { return nil }
        let params = queryItems(url)
        let id: UUID?
        if let raw = params["id"] {
            guard let parsed = UUID(uuidString: raw) else { return nil }
            id = parsed
        } else { id = nil }
        if id != nil && !["", "open", "append"].contains(action) { return nil }
        switch action {
        case "", "open":
            return id.map { .openNote(id: $0) } ?? .open
        case "new", "create", "note":
            return .newNote(text: params["text"])
        case "search", "find":
            guard let q = params["query"] ?? params["q"] else { return nil }
            return .search(query: q)
        case "append":
            guard let t = params["text"], !t.isEmpty else { return nil }
            return id.map { .appendToNote(id: $0, text: t) } ?? .append(text: t)
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
