import ContextStore
import Foundation

public enum DeliveryTarget: Codable, Equatable, Hashable, Sendable {
    case clipboard
    /// The kept-current file under `.context/projects/`.
    case file
    case harness(HarnessKind)
    case router

    public var displayName: String {
        switch self {
        case .clipboard: "Clipboard"
        case .file: "Context file"
        case .harness(let kind): kind.displayName
        case .router: "Constellation router"
        }
    }
}

public enum DeliveryError: Error, Equatable, Sendable {
    /// A connector that exists as an interface but is not built yet.
    case notConnected(String)
    case failed(String)

    public var message: String {
        switch self {
        case .notConnected(let why), .failed(let why): why
        }
    }
}

/// Puts a project's assembled context into one AI harness. Each harness
/// gets its own implementation; the MVP ships stubs (Vision § Injection).
public protocol HarnessConnector: Sendable {
    var kind: HarnessKind { get }
    func deliver(_ context: AssembledContext) async throws
}

/// Pushes project context into the Constellation router's store, so the
/// router can inject it into any harness using its endpoint.
public protocol RouterSync: Sendable {
    func push(_ context: AssembledContext) async throws
}

public struct StubHarnessConnector: HarnessConnector {
    public let kind: HarnessKind

    public init(kind: HarnessKind) {
        self.kind = kind
    }

    public func deliver(_ context: AssembledContext) async throws {
        throw DeliveryError.notConnected(
            "Direct delivery to \(kind.displayName) isn't built yet. Import the context file instead."
        )
    }
}

public struct StubRouterSync: RouterSync {
    public init() {}

    public func push(_ context: AssembledContext) async throws {
        throw DeliveryError.notConnected("Router sync isn't built yet. The context file stays current on this Mac.")
    }
}

/// One delivery attempt, as written to `.context/deliveries.jsonl`.
/// Holds sizes and outcomes, never the context text itself.
public struct DeliveryRecord: Codable, Equatable, Sendable {
    public var date: Date
    public var project: String
    public var target: DeliveryTarget
    public var characters: Int
    public var ok: Bool
    public var message: String?

    public init(date: Date = Date(), project: String, target: DeliveryTarget, characters: Int, ok: Bool, message: String? = nil) {
        self.date = date
        self.project = project
        self.target = target
        self.characters = characters
        self.ok = ok
        self.message = message
    }
}

public struct DeliveryLog: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ record: DeliveryRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var line = try? encoder.encode(record) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    public func records() -> [DeliveryRecord] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(DeliveryRecord.self, from: Data($0.utf8)) }
    }
}

/// Delivers assembled context to targets and records each attempt.
/// Clipboard delivery is the caller's job (it owns the pasteboard); this
/// writes the file, calls connectors, and logs.
public struct ContextDelivery: Sendable {
    public let log: DeliveryLog
    public var harnesses: [HarnessKind: any HarnessConnector]
    public var router: any RouterSync

    public init(
        log: DeliveryLog,
        harnesses: [HarnessKind: any HarnessConnector] = Dictionary(uniqueKeysWithValues: HarnessKind.allCases.map { ($0, StubHarnessConnector(kind: $0)) }),
        router: any RouterSync = StubRouterSync()
    ) {
        self.log = log
        self.harnesses = harnesses
        self.router = router
    }

    /// Writes the kept-current file only when its text changed, so
    /// harnesses watching it don't see churn.
    @discardableResult
    public func writeFile(_ context: AssembledContext, for project: ProjectFiles) throws -> Bool {
        let url = project.output
        if (try? String(contentsOf: url, encoding: .utf8)) == context.text { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try context.text.write(to: url, atomically: true, encoding: .utf8)
        log.append(DeliveryRecord(project: context.project, target: .file, characters: context.text.count, ok: true))
        return true
    }

    public func recordClipboard(_ context: AssembledContext) {
        log.append(DeliveryRecord(project: context.project, target: .clipboard, characters: context.text.count, ok: true))
    }

    /// Sends to every harness and the router the project is bound to.
    /// Returns one result per target; failures are logged, not thrown.
    public func deliverBound(_ context: AssembledContext, manifest: ProjectManifest) async -> [(DeliveryTarget, DeliveryError?)] {
        var results: [(DeliveryTarget, DeliveryError?)] = []
        for kind in manifest.harnesses {
            let target = DeliveryTarget.harness(kind)
            do {
                guard let connector = harnesses[kind] else { throw DeliveryError.notConnected("\(kind.displayName) isn't available.") }
                try await connector.deliver(context)
                results.append((target, nil))
            } catch {
                results.append((target, error as? DeliveryError ?? .failed(String(describing: error))))
            }
        }
        if manifest.routerSync {
            do {
                try await router.push(context)
                results.append((.router, nil))
            } catch {
                results.append((.router, error as? DeliveryError ?? .failed(String(describing: error))))
            }
        }
        for (target, error) in results {
            log.append(DeliveryRecord(
                project: context.project, target: target, characters: context.text.count,
                ok: error == nil, message: error?.message
            ))
        }
        return results
    }
}
