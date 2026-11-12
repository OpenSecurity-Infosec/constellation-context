import Foundation

/// Anytype desktop's local API, v1 (`Anytype-Version: 2025-11-08`).
/// Reference: https://developers.anytype.io/docs/reference
public enum AnytypeAPI {
    public static let version = "2025-11-08"
    public static let baseURL = URL(string: "http://127.0.0.1:31009")!
    /// Layouts that hold writing. Sets, collections, chats, and
    /// participants are containers or people, not notes.
    public static let noteLayouts: Set<String> = ["basic", "note", "action", "bookmark", "profile"]
}

public struct AnytypeRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var body: Data?

    public init(method: String, path: String, query: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }
}

/// Sends one request. Production uses `URLSessionAnytypeTransport`;
/// tests use an in-memory fake of the Anytype server.
public protocol AnytypeTransport: Sendable {
    func send(_ request: AnytypeRequest, apiKey: String?) async throws -> (status: Int, data: Data)
}

public struct URLSessionAnytypeTransport: AnytypeTransport {
    public let baseURL: URL

    public init(baseURL: URL = AnytypeAPI.baseURL) {
        self.baseURL = baseURL
    }

    public func send(_ request: AnytypeRequest, apiKey: String?) async throws -> (status: Int, data: Data) {
        var components = URLComponents(url: baseURL.appendingPathComponent(request.path), resolvingAgainstBaseURL: false)
        if !request.query.isEmpty {
            components?.queryItems = request.query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw VaultError.invalid("Bad Anytype URL.") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = request.method
        req.setValue(AnytypeAPI.version, forHTTPHeaderField: "Anytype-Version")
        if let apiKey { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        if let body = request.body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw VaultError.unavailable("Anytype isn't reachable. Open Anytype and try again.")
        }
    }
}

// MARK: - Wire types

public struct AnytypeSpace: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct AnytypeTag: Codable, Equatable, Sendable {
    public var id: String
    public var key: String?
    public var name: String

    public init(id: String, key: String? = nil, name: String) {
        self.id = id
        self.key = key
        self.name = name
    }
}

public struct AnytypeType: Codable, Equatable, Sendable {
    public var key: String
    public var name: String?

    public init(key: String, name: String? = nil) {
        self.key = key
        self.name = name
    }
}

public enum AnytypePropertyValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case select(AnytypeTag?)
    case multiSelect([AnytypeTag])
    case date(String)
    case files([String])
    case checkbox(Bool)
    case url(String)
    case email(String)
    case phone(String)
    case objects([String])
    case unknown
}

public struct AnytypeProperty: Decodable, Equatable, Sendable {
    public var id: String
    public var key: String
    public var name: String?
    public var format: String
    public var value: AnytypePropertyValue

    enum CodingKeys: String, CodingKey {
        case id, key, name, format, text, number, select, date, files, checkbox, url, email, phone, objects
        case multiSelect = "multi_select"
    }

    public init(id: String, key: String, name: String? = nil, format: String, value: AnytypePropertyValue) {
        self.id = id
        self.key = key
        self.name = name
        self.format = format
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        key = try c.decode(String.self, forKey: .key)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        format = try c.decode(String.self, forKey: .format)
        switch format {
        case "text": value = .text(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "number": value = (try c.decodeIfPresent(Double.self, forKey: .number)).map(AnytypePropertyValue.number) ?? .unknown
        case "select": value = .select(try c.decodeIfPresent(AnytypeTag.self, forKey: .select))
        case "multi_select": value = .multiSelect(try c.decodeIfPresent([AnytypeTag].self, forKey: .multiSelect) ?? [])
        case "date": value = (try c.decodeIfPresent(String.self, forKey: .date)).map(AnytypePropertyValue.date) ?? .unknown
        case "files": value = .files(try c.decodeIfPresent([String].self, forKey: .files) ?? [])
        case "checkbox": value = .checkbox(try c.decodeIfPresent(Bool.self, forKey: .checkbox) ?? false)
        case "url": value = .url(try c.decodeIfPresent(String.self, forKey: .url) ?? "")
        case "email": value = .email(try c.decodeIfPresent(String.self, forKey: .email) ?? "")
        case "phone": value = .phone(try c.decodeIfPresent(String.self, forKey: .phone) ?? "")
        case "objects": value = .objects(try c.decodeIfPresent([String].self, forKey: .objects) ?? [])
        default: value = .unknown
        }
    }
}

public struct AnytypeObject: Decodable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var snippet: String?
    public var layout: String?
    public var archived: Bool?
    public var markdown: String?
    public var type: AnytypeType?
    public var properties: [AnytypeProperty]?

    public init(
        id: String, name: String? = nil, snippet: String? = nil, layout: String? = "basic",
        archived: Bool? = false, markdown: String? = nil, type: AnytypeType? = nil, properties: [AnytypeProperty]? = nil
    ) {
        self.id = id
        self.name = name
        self.snippet = snippet
        self.layout = layout
        self.archived = archived
        self.markdown = markdown
        self.type = type
        self.properties = properties
    }

    /// `last_modified_date`, when Anytype reports it.
    public var modified: Date? {
        for p in properties ?? [] where p.key == "last_modified_date" {
            if case .date(let s) = p.value { return AnytypeDate.parse(s) }
        }
        return nil
    }
}

struct Page<T: Decodable>: Decodable {
    struct Pagination: Decodable {
        var hasMore: Bool
        enum CodingKeys: String, CodingKey { case hasMore = "has_more" }
    }

    var data: [T]
    var pagination: Pagination?
}

struct ObjectEnvelope: Decodable { var object: AnytypeObject }

enum AnytypeDate {
    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withFullDate]
        return f.date(from: s)
    }
}

// MARK: - Client

public struct AnytypeClient: Sendable {
    public let transport: AnytypeTransport
    public let apiKey: String?

    public init(transport: AnytypeTransport = URLSessionAnytypeTransport(), apiKey: String?) {
        self.transport = transport
        self.apiKey = apiKey
    }

    /// Step 1 of linking: Anytype shows a 4-digit code to the user.
    public func startChallenge(appName: String = "Context") async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["app_name": appName])
        let data = try await call(AnytypeRequest(method: "POST", path: "/v1/auth/challenges", body: body))
        struct R: Decodable { var challenge_id: String }
        return try JSONDecoder().decode(R.self, from: data).challenge_id
    }

    /// Step 2 of linking: trade the code for an API key.
    public func exchange(challengeID: String, code: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["challenge_id": challengeID, "code": code])
        let data = try await call(AnytypeRequest(method: "POST", path: "/v1/auth/api_keys", body: body))
        struct R: Decodable { var api_key: String }
        return try JSONDecoder().decode(R.self, from: data).api_key
    }

    public func spaces() async throws -> [AnytypeSpace] {
        try await paged(path: "/v1/spaces")
    }

    public func objects(space: String) async throws -> [AnytypeObject] {
        try await paged(path: "/v1/spaces/\(space)/objects")
    }

    public func search(space: String, query: String) async throws -> [AnytypeObject] {
        let body = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "sort": ["direction": "desc", "property_key": "last_modified_date"],
        ])
        let data = try await call(AnytypeRequest(
            method: "POST", path: "/v1/spaces/\(space)/search", query: ["limit": "100"], body: body
        ))
        return try JSONDecoder().decode(Page<AnytypeObject>.self, from: data).data
    }

    public func object(space: String, id: String) async throws -> AnytypeObject {
        let data = try await call(AnytypeRequest(
            method: "GET", path: "/v1/spaces/\(space)/objects/\(id)", query: ["format": "md"]
        ))
        return try JSONDecoder().decode(ObjectEnvelope.self, from: data).object
    }

    /// Options of a select or multi-select property.
    public func tags(space: String, propertyID: String) async throws -> [AnytypeTag] {
        try await paged(path: "/v1/spaces/\(space)/properties/\(propertyID)/tags")
    }

    public func create(space: String, typeKey: String, name: String, body markdown: String) async throws -> AnytypeObject {
        let body = try JSONSerialization.data(withJSONObject: ["type_key": typeKey, "name": name, "body": markdown])
        let data = try await call(AnytypeRequest(method: "POST", path: "/v1/spaces/\(space)/objects", body: body))
        return try JSONDecoder().decode(ObjectEnvelope.self, from: data).object
    }

    /// PATCH with only the fields that changed. `properties` entries are
    /// `{"key": k, "<format>": value}` as the API expects.
    public func update(space: String, id: String, fields: [String: Any]) async throws -> AnytypeObject {
        let body = try JSONSerialization.data(withJSONObject: fields)
        let data = try await call(AnytypeRequest(method: "PATCH", path: "/v1/spaces/\(space)/objects/\(id)", body: body))
        return try JSONDecoder().decode(ObjectEnvelope.self, from: data).object
    }

    private func paged<T: Decodable>(path: String) async throws -> [T] {
        var out: [T] = []
        var offset = 0
        let limit = 500
        while true {
            let data = try await call(AnytypeRequest(
                method: "GET", path: path, query: ["offset": "\(offset)", "limit": "\(limit)"]
            ))
            let page = try JSONDecoder().decode(Page<T>.self, from: data)
            out += page.data
            guard page.pagination?.hasMore == true, !page.data.isEmpty else { return out }
            offset += page.data.count
        }
    }

    /// Maps HTTP status to `VaultError`, retrying once on the documented
    /// rate limit (burst 60, then 1 request per second).
    private func call(_ request: AnytypeRequest) async throws -> Data {
        var attempt = 0
        while true {
            let (status, data) = try await transport.send(request, apiKey: apiKey)
            switch status {
            case 200..<300: return data
            case 401, 403: throw VaultError.unauthorized
            case 404, 410: throw VaultError.notFound
            case 429:
                attempt += 1
                guard attempt < 2 else { throw VaultError.rateLimited }
                try await Task.sleep(nanoseconds: 1_100_000_000)
            default:
                struct E: Decodable { var message: String? }
                let message = (try? JSONDecoder().decode(E.self, from: data))?.message ?? "HTTP \(status)"
                throw VaultError.invalid("Anytype: \(message)")
            }
        }
    }
}
