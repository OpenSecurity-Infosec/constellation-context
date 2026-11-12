import ContextVault
import Foundation

/// In-memory stand-in for Anytype's local API (v1, 2025-11-08), shaped
/// after the documented request and response JSON.
final class FakeAnytype: AnytypeTransport, @unchecked Sendable {
    struct Property {
        var key: String
        var format: String
        var value: Any?
        var options: [AnytypeTag] = []
    }

    struct Object {
        var id: String
        var name: String
        var markdown: String
        var typeKey = "page"
        var layout = "basic"
        var archived = false
        var properties: [Property] = []
        var modified = Date(timeIntervalSince1970: 1_790_000_000)
    }

    let apiKey = "test-key"
    let code = "1234"
    let spaceID = "space-1"
    private let lock = NSLock()
    private var objects: [String: Object] = [:]
    private var order: [String] = []
    private var nextID = 1
    private(set) var requests: [AnytypeRequest] = []
    /// Responds 429 to this many upcoming requests.
    var rateLimitNext = 0

    func add(_ object: Object) {
        lock.withLock {
            objects[object.id] = object
            order.append(object.id)
        }
    }

    func object(_ id: String) -> Object? { lock.withLock { objects[id] } }

    func send(_ request: AnytypeRequest, apiKey: String?) async throws -> (status: Int, data: Data) {
        lock.withLock { handle(request, apiKey: apiKey) }
    }

    private func handle(_ r: AnytypeRequest, apiKey key: String?) -> (status: Int, data: Data) {
        requests.append(r)
        if rateLimitNext > 0 {
            rateLimitNext -= 1
            return error(429, "rate_limit_exceeded")
        }
        let body = r.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let parts = r.path.split(separator: "/").map(String.init)
        switch (r.method, parts) {
        case ("POST", ["v1", "auth", "challenges"]):
            return json(201, ["challenge_id": "challenge-1"])
        case ("POST", ["v1", "auth", "api_keys"]):
            guard body["challenge_id"] as? String == "challenge-1", body["code"] as? String == code else {
                return error(401, "unauthorized")
            }
            return json(201, ["api_key": apiKey])
        default:
            break
        }
        guard key == apiKey else { return error(401, "unauthorized") }
        switch (r.method, parts) {
        case ("GET", ["v1", "spaces"]):
            return page([["id": spaceID, "name": "Personal", "object": "space"]], r)
        case ("GET", ["v1", "spaces", spaceID, "objects"]):
            return page(order.compactMap { objects[$0] }.map { encode($0, body: false) }, r)
        case ("POST", ["v1", "spaces", spaceID, "search"]):
            let q = (body["query"] as? String ?? "").lowercased()
            let hits = order.compactMap { objects[$0] }.filter {
                q.isEmpty || $0.name.lowercased().contains(q) || $0.markdown.lowercased().contains(q)
            }
            return page(hits.map { encode($0, body: false) }, r)
        case ("POST", ["v1", "spaces", spaceID, "objects"]):
            let id = "obj-\(nextID)"
            nextID += 1
            let o = Object(
                id: id, name: body["name"] as? String ?? "", markdown: body["body"] as? String ?? "",
                typeKey: body["type_key"] as? String ?? "page"
            )
            objects[id] = o
            order.append(id)
            return json(201, ["object": encode(o, body: true)])
        case ("GET", let p) where p.count == 6 && p[3] == "properties" && p[5] == "tags":
            let key = p[4].replacingOccurrences(of: "prop-", with: "")
            let options = objects.values.flatMap { $0.properties }.first { $0.key == key }?.options ?? []
            return page(options.map(tagJSON), r)
        case ("GET", let p) where p.count == 5 && p[3] == "objects":
            guard let o = objects[p[4]], !o.archived else { return error(404, "object_not_found") }
            return json(200, ["object": encode(o, body: true)])
        case ("PATCH", let p) where p.count == 5 && p[3] == "objects":
            guard var o = objects[p[4]] else { return error(404, "object_not_found") }
            if let md = body["markdown"] as? String { o.markdown = md }
            if let name = body["name"] as? String { o.name = name }
            if let type = body["type_key"] as? String { o.typeKey = type }
            for link in body["properties"] as? [[String: Any]] ?? [] {
                guard let k = link["key"] as? String, let i = o.properties.firstIndex(where: { $0.key == k }) else {
                    return error(400, "bad_request")
                }
                let format = o.properties[i].format
                switch format {
                case "select":
                    let id = link["select"] as? String
                    o.properties[i].value = o.properties[i].options.first { $0.key == id || $0.id == id }
                case "multi_select":
                    let ids = link["multi_select"] as? [String] ?? []
                    o.properties[i].value = ids.compactMap { id in o.properties[i].options.first { $0.key == id || $0.id == id } }
                default:
                    o.properties[i].value = link[format]
                }
            }
            o.modified = o.modified.addingTimeInterval(60)
            objects[o.id] = o
            return json(200, ["object": encode(o, body: true)])
        default:
            return error(404, "object_not_found")
        }
    }

    private func encode(_ o: Object, body: Bool) -> [String: Any] {
        var props: [[String: Any]] = o.properties.map { p in
            var d: [String: Any] = ["id": "prop-\(p.key)", "key": p.key, "name": p.key, "format": p.format, "object": "property"]
            switch p.value {
            case let tag as AnytypeTag: d[p.format] = tagJSON(tag)
            case let tags as [AnytypeTag]: d[p.format] = tags.map(tagJSON)
            case let v?: d[p.format] = v
            case nil: break
            }
            return d
        }
        props.append([
            "id": "prop-lmd", "key": "last_modified_date", "name": "Last modified", "format": "date",
            "date": ISO8601DateFormatter().string(from: o.modified), "object": "property",
        ])
        var d: [String: Any] = [
            "id": o.id, "name": o.name, "layout": o.layout, "archived": o.archived, "object": "object",
            "space_id": spaceID, "snippet": String(o.markdown.prefix(80)),
            "type": ["key": o.typeKey, "name": o.typeKey.capitalized, "object": "type"],
            "properties": props,
        ]
        if body { d["markdown"] = o.markdown }
        return d
    }

    private func tagJSON(_ t: AnytypeTag) -> [String: Any] {
        ["id": t.id, "key": t.key ?? t.id, "name": t.name, "object": "tag", "color": "grey"]
    }

    private func page(_ data: [[String: Any]], _ r: AnytypeRequest) -> (status: Int, data: Data) {
        let offset = Int(r.query["offset"] ?? "0") ?? 0
        let limit = Int(r.query["limit"] ?? "100") ?? 100
        let slice = Array(data.dropFirst(offset).prefix(limit))
        return json(200, [
            "data": slice,
            "pagination": ["has_more": offset + slice.count < data.count, "limit": limit, "offset": offset, "total": data.count],
        ])
    }

    private func json(_ status: Int, _ object: [String: Any]) -> (status: Int, data: Data) {
        (status, (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }

    private func error(_ status: Int, _ code: String) -> (status: Int, data: Data) {
        json(status, ["code": code, "message": code, "object": "error", "status": status])
    }
}
