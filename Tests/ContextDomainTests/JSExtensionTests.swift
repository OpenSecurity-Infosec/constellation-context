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

    @Test func loadFromFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "function run(i){return 'a';}".write(to: dir.appendingPathComponent("a.js"), atomically: true, encoding: .utf8)
        try "not js".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let loaded = JSExtension.load(from: dir)
        #expect(loaded.map(\.commandName) == ["a"])
    }
}
