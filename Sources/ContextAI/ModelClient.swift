import Foundation

/// Where AI requests go. Default: the CXN router's OpenAI-compatible
/// endpoint with `gpt-6.1-terra`, as in the local opencode config.
public struct ModelConfig: Equatable, Sendable {
    public var baseURL: URL
    public var model: String

    public init(baseURL: URL, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    public static let defaultBaseURL = "https://infer.cxn.sh/v1"
    public static let defaultModel = "gpt-6.1-terra"

    public static var standard: ModelConfig {
        ModelConfig(baseURL: URL(string: defaultBaseURL) ?? URL(fileURLWithPath: "/"), model: defaultModel)
    }

    /// Host shown to the user so they know where note text is sent.
    public var hostLabel: String { baseURL.host ?? baseURL.absoluteString }
}

public enum ModelError: Error, Equatable, Sendable {
    case missingKey
    case unauthorized
    case rateLimited
    case unavailable(String)
    case badResponse(String)

    public var message: String {
        switch self {
        case .missingKey: "Add an API key in Settings → AI."
        case .unauthorized: "The model endpoint rejected the API key. Check Settings → AI."
        case .rateLimited: "The model endpoint is busy. Try again in a moment."
        case .unavailable(let why), .badResponse(let why): why
        }
    }
}

public protocol ModelTransport: Sendable {
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (status: Int, data: Data)
}

public struct URLSessionModelTransport: ModelTransport {
    public init() {}

    public func post(_ url: URL, headers: [String: String], body: Data) async throws -> (status: Int, data: Data) {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpBody = body
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ModelError.unavailable("Couldn't reach \(url.host ?? "the model endpoint"). Check your connection.")
        }
    }
}

/// Minimal OpenAI-compatible chat completion client: one system and one
/// user message in, the assistant's text out. No streaming in the MVP.
public struct ModelClient: Sendable {
    public var config: ModelConfig
    public var apiKey: String?
    public var transport: any ModelTransport

    public init(config: ModelConfig = .standard, apiKey: String?, transport: any ModelTransport = URLSessionModelTransport()) {
        self.config = config
        self.apiKey = apiKey
        self.transport = transport
    }

    public func complete(system: String, user: String) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw ModelError.missingKey }
        let body = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ])
        let url = config.baseURL.appendingPathComponent("chat/completions")
        let (status, data) = try await transport.post(url, headers: [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
        ], body: body)
        switch status {
        case 200..<300: break
        case 401, 403: throw ModelError.unauthorized
        case 429: throw ModelError.rateLimited
        default:
            throw ModelError.unavailable("The model endpoint answered \(status). Try again or check Settings → AI.")
        }
        return try Self.text(from: data)
    }

    /// `choices[0].message.content`, as a string or an array of text parts.
    static func text(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { throw ModelError.badResponse("The model's reply wasn't in the expected format.") }
        if let s = message["content"] as? String { return s }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        throw ModelError.badResponse("The model's reply had no text.")
    }
}
