import ContextDomain
import Foundation
import Testing

@Suite struct JSExtensionTests {
    @Test func headerParses() {
        let script = JSExtension.parseHeader(
            fileName: "shout.js",
            source: "// name: shout — hint: Uppercase it\nfunction run(i){return i.text;}"
        )
        #expect(script?.commandName == "shout")
        #expect(script?.hint == "Uppercase it")
    }

    @Test func headerFallsBackToFileName() {
        let script = JSExtension.parseHeader(fileName: "My Cool.js", source: "function run(i){return 'x';}")
        #expect(script?.commandName == "my_cool")
    }

    @Test func replacementRuns() {
        let script = JSExtension.parseHeader(
            fileName: "t.js",
            source: "function run(input) { return { replacement: input.token + '!'}; }"
        )!
        let out = JSExtension.run(script, input: .init(text: "hi", token: "::t", selection: "", nowISO: "2026-09-27"))
        #expect(out == .replacement("::t!"))
    }

    @Test func fullTextRuns() {
        let script = JSExtension.parseHeader(
            fileName: "u.js",
            source: "function run(input) { return { fullText: input.text.toUpperCase() }; }"
        )!
        let out = JSExtension.run(script, input: .init(text: "hi", token: "::u", selection: "", nowISO: ""))
        #expect(out == .fullText("HI"))
    }

    @Test func bareStringRuns() {
        let script = JSExtension.parseHeader(
            fileName: "s.js",
            source: "function run(input) { return 'plain'; }"
        )!
        #expect(JSExtension.run(script, input: .init(text: "", token: "", selection: "", nowISO: "")) == .replacement("plain"))
    }

    @Test func missingRunFnYieldsNil() {
        let script = JSExtension.parseHeader(fileName: "n.js", source: "var x = 1;")!
        #expect(JSExtension.run(script, input: .init(text: "", token: "", selection: "", nowISO: "")) == nil)
    }

    @Test func noNetworkBridge() {
        // fetch/XHR are undefined in the sandbox; scripts cannot call out.
        let script = JSExtension.parseHeader(
            fileName: "net.js",
            source: "function run(input) { return { replacement: String(typeof fetch) }; }"
        )!
        let out = JSExtension.run(script, input: .init(text: "", token: "", selection: "", nowISO: ""))
        #expect(out == .replacement("undefined"))
    }

    private func script(_ source: String) -> JSExtension.Script {
        JSExtension.parseHeader(fileName: "x.js", source: source)!
    }

    private func runFailure(
        _ source: String, timeout: TimeInterval = JSExtension.defaultTimeout
    ) -> JSExtension.ExtensionError? {
        let result = JSExtension.runResult(
            script(source),
            input: .init(text: "", token: "::x", selection: "", nowISO: ""),
            timeout: timeout
        )
        if case .failure(let error) = result { return error }
        return nil
    }

    @Test func thrownExceptionSurfaces() {
        let error = runFailure("function run(i) { throw new Error('boom goes the script'); }")
        #expect(error?.message.contains("boom goes the script") == true)
    }

    @Test func syntaxErrorSurfaces() {
        let error = runFailure("function run( {")
        if case .scriptError(let detail) = error {
            #expect(!detail.isEmpty)
        } else {
            Issue.record("expected scriptError, got \(String(describing: error))")
        }
    }

    @Test func missingRunReported() {
        #expect(runFailure("var x = 1;") == .missingRunFunction)
    }

    @Test func runNotCallableFails() {
        #expect(runFailure("var run = 3;") != nil)
    }

    @Test func infiniteLoopTimesOutAndTerminates() {
        let start = Date()
        let error = runFailure("function run(i) { while (true) {} }", timeout: 0.2)
        let elapsed = Date().timeIntervalSince(start)
        if case .timedOut = error {} else {
            Issue.record("expected timedOut, got \(String(describing: error))")
        }
        #expect(error?.message.contains("timed out") == true)
        #expect(elapsed < 10)
    }

    @Test func topLevelInfiniteLoopTimesOut() {
        let error = runFailure("while (true) {}\nfunction run(i) { return 'x'; }", timeout: 0.2)
        if case .timedOut = error {} else {
            Issue.record("expected timedOut, got \(String(describing: error))")
        }
    }

    @Test func briefBusyWorkUnderTimeoutRuns() {
        let out = JSExtension.runResult(
            script("function run(i) { var t = Date.now(); while (Date.now() - t < 20) {} return 'done'; }"),
            input: .init(text: "", token: "", selection: "", nowISO: "")
        )
        #expect((try? out.get()) == .replacement("done"))
    }

    @Test func invalidReturnsReported() {
        if case .invalidReturn = runFailure("function run(i) { return 42; }") {} else {
            Issue.record("expected invalidReturn for number")
        }
        if case .invalidReturn = runFailure("function run(i) { return; }") {} else {
            Issue.record("expected invalidReturn for undefined")
        }
        let keys = runFailure("function run(i) { return { nope: 1 }; }")
        #expect(keys?.message.contains("nope") == true)
        #expect(runFailure("function run(i) { return { error: 'nah' }; }") == .scriptError("nah"))
    }

    @Test func argsPassedToScript() {
        let out = JSExtension.run(
            script("function run(input) { return input.args.join('-'); }"),
            input: .init(text: "", token: "::x", selection: "", nowISO: "", args: ["a", "b", "c"])
        )
        #expect(out == .replacement("a-b-c"))
    }

    @Test func noNetworkGlobalsAtAll() {
        let out = JSExtension.run(
            script("function run(i) { return [typeof fetch, typeof XMLHttpRequest, typeof WebSocket].join(','); }"),
            input: .init(text: "", token: "", selection: "", nowISO: "")
        )
        #expect(out == .replacement("undefined,undefined,undefined"))
    }

    @Test func appendRuns() {
        let out = JSExtension.run(
            script("function run(i) { return { append: 'tail' }; }"),
            input: .init(text: "head", token: "", selection: "", nowISO: "")
        )
        #expect(out == .append("tail"))
    }

    @Test func loadReportNamesUnreadableFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "function run(i){return 'a';}".write(to: dir.appendingPathComponent("good.js"), atomically: true, encoding: .utf8)
        try Data([0xFF, 0xFE, 0x00, 0x80]).write(to: dir.appendingPathComponent("bad.js"))
        let report = JSExtension.loadReport(from: dir)
        #expect(report.scripts.map(\.commandName) == ["good"])
        #expect(report.failures.map(\.fileName) == ["bad.js"])
    }

    @Test func loadFromFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "function run(i){return 'a';}".write(to: dir.appendingPathComponent("a.js"), atomically: true, encoding: .utf8)
        try "not js".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let loaded = JSExtension.load(from: dir)
        #expect(loaded.map(\.commandName) == ["a"])
    }
}
