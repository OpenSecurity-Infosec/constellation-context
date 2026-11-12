import Foundation
import JavaScriptCore

/// Local `.js` extensions folder. Scripts declare commands the `::`
/// autocomplete picks up alongside native builtins.
///
/// Script contract (ES5-safe):
/// ```js
/// // name: shout — hint: Uppercase the note body
/// function run(input) { return { replacement: input.text.toUpperCase() }; }
/// ```
/// `input` is `{ text, token, selection, now }`. Return shapes:
/// - `{ replacement: "..." }` — replaces the `::token` range
/// - `{ fullText: "..." }` — replaces the whole buffer
/// - `{ append: "..." }` — appends to the buffer
/// - a bare string — treated as `{ replacement: string }`
///
/// Privacy: scripts run in a bare JSContext with no fetch/XHR/network
/// bridge. `allowNetwork` stays false unless Settings opts in, and even
/// then only exposes a synchronous-blocking-free stub — scripts declare
/// intent; the host performs fetches. Default OFF.
public enum JSExtension: Sendable {
    public struct Script: Equatable, Sendable {
        public var fileName: String
        public var commandName: String
        public var hint: String
        public var source: String

        public init(fileName: String, commandName: String, hint: String, source: String) {
            self.fileName = fileName
            self.commandName = commandName
            self.hint = hint
            self.source = source
        }
    }

    public struct Input: Sendable {
        public var text: String
        public var token: String
        public var selection: String
        public var nowISO: String
        /// Parenthesised `::name(a, b)` arguments, exposed as `input.args`.
        public var args: [String]

        public init(text: String, token: String, selection: String, nowISO: String, args: [String] = []) {
            self.text = text
            self.token = token
            self.selection = selection
            self.nowISO = nowISO
            self.args = args
        }
    }

    public enum Output: Equatable, Sendable {
        case replacement(String)
        case fullText(String)
        case append(String)
    }

    /// Why a script did not produce an edit. `message` is the one-line
    /// form the editor surfaces; nothing fails silently.
    public enum ExtensionError: Error, Equatable, Sendable {
        /// Syntax error at load, a thrown exception, or `{ error: "…" }`.
        case scriptError(String)
        /// The script defines no callable global `run`.
        case missingRunFunction
        /// The JS execution time limit fired and terminated the script.
        case timedOut(seconds: Double)
        /// `run` returned something unusable (number, nothing, wrong keys).
        case invalidReturn(String)
        case contextUnavailable

        public var message: String {
            switch self {
            case .scriptError(let detail):
                return "extension error: \(detail)"
            case .missingRunFunction:
                return "extension defines no run(input) function"
            case .timedOut(let seconds):
                return "extension timed out after \(trimmedSeconds(seconds))s and was stopped"
            case .invalidReturn(let detail):
                return "extension returned \(detail) — return a string or { replacement } / { fullText } / { append }"
            case .contextUnavailable:
                return "JavaScript runtime unavailable"
            }
        }

        private func trimmedSeconds(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }
    }

    /// A `.js` file that could not be loaded as an extension.
    public struct LoadFailure: Equatable, Sendable {
        public var fileName: String
        public var message: String
        public init(fileName: String, message: String) {
            self.fileName = fileName
            self.message = message
        }
    }

    /// Parses `// name: x — hint: y` headers (both `—` and `-` accepted).
    public static func parseHeader(fileName: String, source: String) -> Script? {
        let base = (fileName as NSString).deletingPathExtension
            .replacingOccurrences(of: #"[^a-zA-Z0-9_-]+"#, with: "_", options: .regularExpression)
        var name = base
        var hint = "JavaScript extension"
        for line in source.components(separatedBy: .newlines).prefix(8) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("//") else { continue }
            let body = t.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if body.lowercased().hasPrefix("name:") {
                var value = body.dropFirst(5).trimmingCharacters(in: .whitespaces)
                // Allow `// name: shout — hint: Uppercase it` on one line.
                if let dash = value.range(of: "—") ?? value.range(of: " - ") {
                    let hintPart = value[dash.upperBound...].trimmingCharacters(in: .whitespaces)
                    if hintPart.lowercased().hasPrefix("hint:") {
                        let h = hintPart.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if !h.isEmpty { hint = h }
                    }
                    value = value[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)
                }
                if !value.isEmpty { name = value }
            } else if body.lowercased().hasPrefix("hint:") {
                let value = body.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { hint = value }
            }
        }
        let commandName = name.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_-]+"#, with: "_", options: .regularExpression)
        guard !commandName.isEmpty else { return nil }
        return Script(fileName: fileName, commandName: commandName, hint: hint, source: source)
    }

    /// Loads all `.js` files from a folder, sorted by file name.
    public static func load(from folder: URL) -> [Script] {
        loadReport(from: folder).scripts
    }

    /// Like `load`, but unreadable or non-UTF-8 `.js` files are reported
    /// instead of silently skipped.
    public static func loadReport(from folder: URL) -> (scripts: [Script], failures: [LoadFailure]) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return ([], []) }
        var scripts: [Script] = []
        var failures: [LoadFailure] = []
        for url in files
            .filter({ $0.pathExtension.lowercased() == "js" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let source = try String(contentsOf: url, encoding: .utf8)
                if let script = parseHeader(fileName: url.lastPathComponent, source: source) {
                    scripts.append(script)
                } else {
                    failures.append(LoadFailure(fileName: url.lastPathComponent, message: "no usable command name"))
                }
            } catch {
                failures.append(LoadFailure(
                    fileName: url.lastPathComponent,
                    message: "could not read as UTF-8: \((error as NSError).localizedDescription)"
                ))
            }
        }
        return (scripts, failures)
    }

    /// Default extensions folder: ~/Library/Application Support/ConstellationContext/Extensions.
    public static func defaultFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ConstellationContext/Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        ensureSamples(in: base)
        return base
    }

    /// Default wall-clock limit for a script run, in seconds.
    public static let defaultTimeout: TimeInterval = 2

    /// Runs a script's `run(input)` in a sandboxed JSContext and reports
    /// failures instead of swallowing them: load/throw errors, a missing
    /// `run`, an unusable return value, and timeouts. The timeout uses
    /// JavaScriptCore's execution time limit, which actually terminates
    /// the script (an infinite loop cannot hang the app).
    /// No network, no file access: `fetch`/`XMLHttpRequest`/`WebSocket`
    /// are absent from the bare context and are explicitly left undefined.
    public static func runResult(
        _ script: Script,
        input: Input,
        allowNetwork: Bool = false,
        timeout: TimeInterval = defaultTimeout
    ) -> Result<Output, ExtensionError> {
        guard let ctx = JSContext() else { return .failure(.contextUnavailable) }
        // Privacy: no fetch/XHR/network bridge, whatever Settings say —
        // `allowNetwork` only ever meant scripts may *declare* fetches for
        // the host to perform; no bridge is installed here.
        _ = allowNetwork

        var exceptionText: String?
        ctx.exceptionHandler = { _, value in
            if let value, exceptionText == nil {
                exceptionText = value.toString()
            }
        }

        // Execution time limit: JSC asks the callback once the budget is
        // spent; answering true terminates the script on the spot.
        let flag = TimeoutFlag()
        let limit = max(timeout, 0.05)
        let group = JSContextGetGroup(ctx.jsGlobalContextRef)
        jsContextGroupSetExecutionTimeLimit(group, limit, { _, clientData in
            if let clientData {
                Unmanaged<TimeoutFlag>.fromOpaque(clientData).takeUnretainedValue().fired = true
            }
            return true
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(flag).toOpaque()))
        defer { jsContextGroupClearExecutionTimeLimit(group) }

        func failureSoFar() -> ExtensionError? {
            if flag.fired { return .timedOut(seconds: limit) }
            if let exceptionText { return .scriptError(exceptionText) }
            return nil
        }

        ctx.evaluateScript("this.fetch = undefined; this.XMLHttpRequest = undefined; this.WebSocket = undefined;")
        ctx.evaluateScript(script.source)
        if let failure = failureSoFar() { return .failure(failure) }

        guard let runFn = ctx.objectForKeyedSubscript("run"), !runFn.isUndefined, !runFn.isNull else {
            return .failure(.missingRunFunction)
        }
        let inputObj = JSValue(newObjectIn: ctx)
        inputObj?.setValue(input.text, forProperty: "text")
        inputObj?.setValue(input.token, forProperty: "token")
        inputObj?.setValue(input.selection, forProperty: "selection")
        inputObj?.setValue(input.nowISO, forProperty: "now")
        inputObj?.setValue(input.args, forProperty: "args")
        guard let result = runFn.call(withArguments: [inputObj as Any]) else {
            if let failure = failureSoFar() { return .failure(failure) }
            return .failure(.missingRunFunction)
        }
        if let failure = failureSoFar() { return .failure(failure) }
        if result.isUndefined || result.isNull {
            return .failure(.invalidReturn(result.isUndefined ? "undefined" : "null"))
        }
        if result.isString {
            return .success(.replacement(result.toString()))
        }
        if let dict = result.toDictionary() as? [String: Any] {
            if let errorText = dict["error"] as? String { return .failure(.scriptError(errorText)) }
            if let full = dict["fullText"] as? String { return .success(.fullText(full)) }
            if let app = dict["append"] as? String { return .success(.append(app)) }
            if let rep = dict["replacement"] as? String { return .success(.replacement(rep)) }
            let keys = dict.keys.sorted().joined(separator: ", ")
            return .failure(.invalidReturn(keys.isEmpty ? "an empty object" : "an object with keys {\(keys)}"))
        }
        if result.isNumber { return .failure(.invalidReturn("a number (\(result.toString() ?? ""))")) }
        if result.isBoolean { return .failure(.invalidReturn("a boolean")) }
        return .failure(.invalidReturn("an unsupported value"))
    }

    /// Runs a script's `run(input)`, returning nil on any failure.
    /// Prefer `runResult` so the user hears why.
    public static func run(_ script: Script, input: Input, allowNetwork: Bool = false) -> Output? {
        try? runResult(script, input: input, allowNetwork: allowNetwork).get()
    }

    /// Mutable box shared with the C timeout callback via clientData.
    private final class TimeoutFlag {
        var fired = false
    }

    private static func ensureSamples(in folder: URL) {
        let samples: [(String, String)] = [
            ("shout.js", "// name: shout — hint: Uppercase the note body\nfunction run(input) { return { fullText: input.text.toUpperCase() }; }\n"),
            ("wordcount.js", "// name: wordcount — hint: Insert word count at caret\nfunction run(input) { var n = input.text.split(/\\s+/).filter(function(w){return w.length>0;}).length; return { replacement: String(n) + ' words' }; }\n"),
        ]
        for (name, source) in samples {
            let url = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? source.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

// JavaScriptCore's execution-time-limit entry points are exported by the
// framework but not declared in its public headers, so bind the C symbols
// directly. Signatures mirror JSContextRefPrivate.h.
private typealias JSShouldTerminateCallback = @convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool

@_silgen_name("JSContextGroupSetExecutionTimeLimit")
private func jsContextGroupSetExecutionTimeLimit(
    _ group: JSContextGroupRef?,
    _ limit: Double,
    _ callback: JSShouldTerminateCallback?,
    _ clientData: UnsafeMutableRawPointer?
)

@_silgen_name("JSContextGroupClearExecutionTimeLimit")
private func jsContextGroupClearExecutionTimeLimit(_ group: JSContextGroupRef?)
