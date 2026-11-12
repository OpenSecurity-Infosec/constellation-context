import Foundation

/// One Anytype space as a linked vault. Objects become Markdown:
/// the body is Anytype's markdown, and `title`, `type`, and every
/// property with a value become frontmatter. Writes send only what
/// changed, so untouched properties are never rewritten.
public struct AnytypeConnector: VaultConnector {
    public let id: String
    public let displayName: String
    public let spaceID: String
    public let client: AnytypeClient
    public var kind: VaultKind { .anytype }

    public init(id: String, displayName: String, spaceID: String, client: AnytypeClient) {
        self.id = id
        self.displayName = displayName
        self.spaceID = spaceID
        self.client = client
    }

    public func list() async throws -> [VaultNoteSummary] {
        try await client.objects(space: spaceID).filter(isNote).map(summary)
    }

    public func search(_ query: String) async throws -> [VaultNoteSummary] {
        try await client.search(space: spaceID, query: query).filter(isNote).map(summary)
    }

    public func read(_ ref: VaultNoteRef) async throws -> VaultNote {
        note(from: try await client.object(space: spaceID, id: ref.noteID))
    }

    @discardableResult
    public func write(_ note: VaultNote) async throws -> VaultNote {
        let current = try await client.object(space: spaceID, id: note.ref.noteID)
        let before = Self.document(for: current)
        var options: [String: [AnytypeTag]] = [:]
        for property in current.properties ?? []
        where ["select", "multi_select"].contains(property.format)
            && note.document.keys.contains(property.key)
            && Self.rendered(before, property.key) != Self.rendered(note.document, property.key)
        {
            options[property.key] = try await client.tags(space: spaceID, propertyID: property.id)
        }
        let fields = try Self.changes(from: current, to: note.document, options: options)
        guard !fields.isEmpty else { return self.note(from: current) }
        return self.note(from: try await client.update(space: spaceID, id: current.id, fields: fields))
    }

    public func create(title: String, body: String) async throws -> VaultNote {
        let doc = MarkdownDocument(parsing: body)
        return note(from: try await client.create(space: spaceID, typeKey: "page", name: title, body: doc.body))
    }

    // MARK: - Mapping

    func isNote(_ object: AnytypeObject) -> Bool {
        object.archived != true && AnytypeAPI.noteLayouts.contains(object.layout ?? "basic")
    }

    func summary(_ object: AnytypeObject) -> VaultNoteSummary {
        let snippet = object.snippet ?? ""
        let title = object.name.flatMap { $0.isEmpty ? nil : $0 }
            ?? snippet.components(separatedBy: .newlines).first ?? "Untitled"
        return VaultNoteSummary(
            ref: VaultNoteRef(vaultID: id, noteID: object.id),
            title: title, snippet: snippet, modified: object.modified
        )
    }

    func note(from object: AnytypeObject) -> VaultNote {
        VaultNote(
            ref: VaultNoteRef(vaultID: id, noteID: object.id),
            document: Self.document(for: object),
            modified: object.modified
        )
    }

    /// Frontmatter for an object, in a stable order: title, type, then
    /// properties as Anytype lists them. Empty values are left out.
    static func document(for object: AnytypeObject) -> MarkdownDocument {
        var doc = MarkdownDocument(body: object.markdown ?? "")
        if let name = object.name, !name.isEmpty { doc.setValue(name, for: "title") }
        if let type = object.type?.key { doc.setValue(type, for: "type") }
        for property in object.properties ?? [] where !skippedKeys.contains(property.key) {
            switch frontmatter(property.value) {
            case .some(.scalar(let s)): doc.setValue(s, for: property.key)
            case .some(.list(let items)): doc.setList(items, for: property.key)
            case .none: continue
            }
        }
        return doc
    }

    /// Keys Context renders itself.
    static let reservedKeys: Set<String> = ["title", "type", "name"]
    /// Properties Anytype updates on its own. In frontmatter they would
    /// change on every read or write; `VaultNote.modified` carries the date.
    static let volatileKeys: Set<String> = ["last_modified_date", "last_opened_date", "last_modified_by"]
    static var skippedKeys: Set<String> { reservedKeys.union(volatileKeys) }

    enum Rendered: Equatable {
        case scalar(String)
        case list([String])
    }

    static func frontmatter(_ value: AnytypePropertyValue) -> Rendered? {
        switch value {
        case .text(let s), .url(let s), .email(let s), .phone(let s), .date(let s):
            return s.isEmpty ? nil : .scalar(s)
        case .number(let n):
            return .scalar(n.rounded() == n && abs(n) < 1e15 ? String(Int64(n)) : String(n))
        case .checkbox(let b):
            return .scalar(b ? "true" : "false")
        case .select(let tag):
            return tag.map { .scalar($0.name) }
        case .multiSelect(let tags):
            return tags.isEmpty ? nil : .list(tags.map(\.name))
        case .files(let ids), .objects(let ids):
            return ids.isEmpty ? nil : .list(ids)
        case .unknown:
            return nil
        }
    }

    /// The PATCH body that turns `current` into `edited`. Throws
    /// `.unsupported` for edits Anytype cannot hold, rather than
    /// silently dropping them.
    static func changes(
        from current: AnytypeObject, to edited: MarkdownDocument, options: [String: [AnytypeTag]] = [:]
    ) throws -> [String: Any] {
        let before = document(for: current)
        var fields: [String: Any] = [:]
        if edited.body != before.body { fields["markdown"] = edited.body }
        if edited.value(for: "title") != before.value(for: "title") {
            fields["name"] = edited.value(for: "title") ?? ""
        }
        if edited.value(for: "type") != before.value(for: "type") {
            guard let type = edited.value(for: "type"), !type.isEmpty else {
                throw VaultError.unsupported("Every Anytype object needs a type.")
            }
            fields["type_key"] = type
        }

        let byKey = Dictionary((current.properties ?? []).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var properties: [[String: Any]] = []
        for key in Set(edited.keys).union(before.keys) where !skippedKeys.contains(key) {
            let old = before.keys.contains(key) ? rendered(before, key) : nil
            let new = edited.keys.contains(key) ? rendered(edited, key) : nil
            guard old != new else { continue }
            guard let property = byKey[key] else {
                throw VaultError.unsupported("Anytype has no property “\(key)” on this object. Add it in Anytype first.")
            }
            properties.append(try link(property, to: new, options: options[key] ?? []))
        }
        if !properties.isEmpty {
            fields["properties"] = properties.sorted { ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "") }
        }
        return fields
    }

    static func rendered(_ doc: MarkdownDocument, _ key: String) -> Rendered {
        guard let entry = doc.entries().first(where: { $0.key == key }) else { return .scalar("") }
        switch entry.value {
        case .scalar(let s): return .scalar(s)
        case .list(let items): return .list(items)
        }
    }

    /// One `PropertyLinkWithValue` for an edited value. Nil `new` means
    /// the key was removed from frontmatter, which clears it.
    static func link(_ property: AnytypeProperty, to new: Rendered?, options: [AnytypeTag] = []) throws -> [String: Any] {
        let key = property.key
        func scalar() -> String {
            switch new {
            case .some(.scalar(let s)): s
            case .some(.list(let items)): items.joined(separator: ", ")
            case .none: ""
            }
        }
        func list() -> [String] {
            switch new {
            case .some(.list(let items)): items
            case .some(.scalar(let s)): s.isEmpty ? [] : [s]
            case .none: []
            }
        }
        switch property.format {
        case "text", "url", "email", "phone":
            return ["key": key, property.format: scalar()]
        case "checkbox":
            return ["key": key, "checkbox": scalar().lowercased() == "true"]
        case "number":
            guard new != nil, let n = Double(scalar()) else {
                throw VaultError.unsupported("“\(key)” must be a number in Anytype.")
            }
            return ["key": key, "number": n]
        case "date":
            guard new != nil, AnytypeDate.parse(scalar()) != nil else {
                throw VaultError.unsupported("“\(key)” must be a date like 2026-11-12 in Anytype.")
            }
            return ["key": key, "date": scalar()]
        case "select":
            let known = options + knownTags(property)
            guard let tag = known.first(where: { $0.name == scalar() }) else {
                throw VaultError.unsupported("“\(key)” has no “\(scalar())” option in Anytype. Add it there first.")
            }
            return ["key": key, "select": tag.key ?? tag.id]
        case "multi_select":
            let known = options + knownTags(property)
            var ids: [String] = []
            for name in list() {
                guard let tag = known.first(where: { $0.name == name }) else {
                    throw VaultError.unsupported("“\(key)” has no “\(name)” option in Anytype. Add it there first.")
                }
                ids.append(tag.key ?? tag.id)
            }
            return ["key": key, "multi_select": ids]
        case "files", "objects":
            return ["key": key, property.format: list()]
        default:
            throw VaultError.unsupported("Context can't edit “\(key)” yet.")
        }
    }

    static func knownTags(_ property: AnytypeProperty) -> [AnytypeTag] {
        switch property.value {
        case .select(let tag): tag.map { [$0] } ?? []
        case .multiSelect(let tags): tags
        default: []
        }
    }
}
