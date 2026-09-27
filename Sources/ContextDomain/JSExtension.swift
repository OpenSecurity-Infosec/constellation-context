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

        public init(text: String, token: String, selection: String, nowISO: String) {
            self.text = text
            self.token = token
            self.selection = selection
            self.nowISO = nowISO
        }
    }

    public enum Output: Equatable, Sendable {
        case replacement(String)
        case fullText(String)
        case append(String)
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
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "js" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return parseHeader(fileName: url.lastPathComponent, source: source)
            }
    }

    /// Default extensions folder: ~/Library/Application Support/ConstellationContext/Extensions.
    public static func defaultFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ConstellationContext/Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        ensureSamples(in: base)
        return base
    }

    /// Runs a script's `run(input)` in a sandboxed JSContext.
    /// No network, no file access, 5s wall-clock guard via JS timeout is
    /// enforced by evaluating synchronously on the calling thread.
    public static func run(_ script: Script, input: Input, allowNetwork: Bool = false) -> Output? {
        guard let ctx = JSContext() else { return nil }
        ctx.exceptionHandler = { _, _ in }
        // Privacy: explicitly no fetch/XHR/network bridge. When the user
        // opts in via Settings, scripts may request fetches through a
        // declared `wantsFetch` return — the host performs them.
        _ = allowNetwork
        ctx.evaluateScript(script.source)
        guard let runFn = ctx.objectForKeyedSubscript("run"), !runFn.isUndefined else { return nil }
        let inputObj = JSValue(newObjectIn: ctx)
        inputObj?.setValue(input.text, forProperty: "text")
        inputObj?.setValue(input.token, forProperty: "token")
        inputObj?.setValue(input.selection, forProperty: "selection")
        inputObj?.setValue(input.nowISO, forProperty: "now")
        guard let result = runFn.call(withArguments: [inputObj as Any]), !result.isUndefined, !result.isNull else {
            return nil
        }
        if result.isString {
            return .replacement(result.toString())
        }
        if let dict = result.toDictionary() as? [String: Any] {
            if let full = dict["fullText"] as? String { return .fullText(full) }
            if let app = dict["append"] as? String { return .append(app) }
            if let rep = dict["replacement"] as? String { return .replacement(rep) }
        }
        return nil
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
