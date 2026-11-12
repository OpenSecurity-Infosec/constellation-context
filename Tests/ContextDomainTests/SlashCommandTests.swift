import ContextDomain
import Foundation
import Testing

@Suite struct SlashCommandTests {
    /// Fixed instant: 2026-09-27 00:00 UTC.
    private var fixedDate: Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: DateComponents(year: 2026, month: 9, day: 27))!
    }

    private func runToken(
        _ token: String,
        in text: String = "",
        selection: Range<Int>? = nil,
        now: Date? = nil
    ) -> Result<SlashCommand.Edit, SlashCommand.CommandError> {
        let invocation = SlashCommand.parseInvocation(token)!
        // Token sits at the end of `text` unless the text already contains it.
        let full = text.contains(token) ? text : text + token
        let start = full.distance(from: full.startIndex, to: full.range(of: token)!.lowerBound)
        return SlashCommand.runResult(
            invocation,
            tokenRange: start..<(start + token.count),
            fullText: full,
            selection: selection,
            now: now ?? fixedDate
        )
    }

    private func replacement(_ token: String, in text: String = "", now: Date? = nil) -> String? {
        try? runToken(token, in: text, now: now).get().replacement
    }

    private func failure(_ token: String, in text: String = "") -> SlashCommand.CommandError? {
        if case .failure(let error) = runToken(token, in: text) { return error }
        return nil
    }

    // MARK: Token + invocation parsing

    @Test func tokenDetected() {
        let found = SlashCommand.token(at: 8, in: "hello ::tod")
        #expect(found?.token == "::tod")
    }

    @Test func tokenNilWithoutOpener() {
        #expect(SlashCommand.token(at: 5, in: "hello") == nil)
    }

    @Test func tokenIncludesParenthesisedArgs() {
        let text = "roll ::random(1, 10) now"
        let found = SlashCommand.token(at: 14, in: text)
        #expect(found?.token == "::random(1, 10)")
        #expect(SlashCommand.fragment(fromToken: found?.token ?? "") == "random")
    }

    @Test func tokenNilPastClosedArgsAndInsideWord() {
        #expect(SlashCommand.token(at: 22, in: "roll ::random(1, 10) now") == nil)
        #expect(SlashCommand.token(at: 8, in: "std::sort") == nil)
    }

    @Test func invocationParsing() {
        let plain = SlashCommand.parseInvocation("::today")
        #expect(plain?.name == "today")
        #expect(plain?.arguments == [])
        #expect(plain?.hasParenthesisedArgs == false)

        let ranged = SlashCommand.parseInvocation("::random(1, 10)")
        #expect(ranged?.arguments == ["1", "10"])

        let quoted = SlashCommand.parseInvocation(#"::upper("a, b")"#)
        #expect(quoted?.arguments == ["a, b"])
        #expect(quoted?.rawArgument == #""a, b""#)

        let typing = SlashCommand.parseInvocation("::upper(hi")
        #expect(typing?.rawArgument == "hi")

        #expect(SlashCommand.parseInvocation("nope") == nil)
        #expect(SlashCommand.parseInvocation("::") == nil)
        #expect(SlashCommand.parseInvocation("::x y)") == nil)
    }

    @Test func splitArgumentsRespectsQuotes() {
        #expect(SlashCommand.splitArguments("a, 'b, c', d") == ["a", "b, c", "d"])
        #expect(SlashCommand.splitArguments("") == [])
        #expect(SlashCommand.splitArguments("  ") == [])
        #expect(SlashCommand.splitArguments("one") == ["one"])
    }

    // MARK: Completions + suggestions

    @Test func completionsFilter() {
        #expect(SlashCommand.completions(matching: "").count == SlashCommand.builtins.count)
        #expect(SlashCommand.completions(matching: "to").map(\.name) == ["today", "tomorrow"])
        let sNames = SlashCommand.completions(matching: "s").map(\.name)
        #expect(sNames.contains("sort_lines"))
        #expect(sNames.contains("shuffle_lines"))
    }

    @Test func completionsAliasAndSubstringFallback() {
        #expect(SlashCommand.completions(matching: "dat").map(\.name).contains("today"))
        #expect(SlashCommand.completions(matching: "ines").map(\.name).contains("sort_lines"))
        #expect(SlashCommand.completions(matching: "zz").isEmpty)
    }

    @Test func suggestionsDidYouMean() {
        #expect(SlashCommand.suggestions(for: "tday").first == "today")
        #expect(SlashCommand.suggestions(for: "sort_line").first == "sort_lines")
        #expect(SlashCommand.suggestions(for: "dedupe").first == "dedupe_lines")
        #expect(SlashCommand.suggestions(for: "zztop").isEmpty)
        #expect(SlashCommand.suggestions(for: "").isEmpty)
    }

    @Test func unknownCommandErrorWithSuggestion() {
        let error = failure("::tday")
        #expect(error?.gutterMessage.contains("did you mean ::today") == true)
        #expect(failure("::zztop")?.gutterMessage.contains("::help lists commands") == true)
        #expect(SlashCommand.run(name: "nope", tokenRange: nil, fullText: "", selection: nil) == nil)
    }

    @Test func unknownSuggestionIncludesExtensionNames() {
        let result = SlashCommand.runResult(
            name: "shoutt", tokenRange: nil, fullText: "", selection: nil, knownNames: ["shout"]
        )
        if case .failure(.unknownCommand(_, let suggestions)) = result {
            #expect(suggestions.contains("shout"))
        } else {
            Issue.record("expected unknownCommand, got \(result)")
        }
    }

    // MARK: Date / time / id inserts

    @Test func todayInsertsISODate() {
        let edit = SlashCommand.run(name: "today", tokenRange: 0..<7, fullText: "::today", selection: nil, now: fixedDate)
        #expect(edit?.replacement == "2026-09-27")
    }

    @Test func dateVariantsAndCustomFormat() {
        #expect(replacement("::tomorrow") == "2026-09-28")
        #expect(replacement("::yesterday") == "2026-09-26")
        #expect(replacement("::today(yyyy/MM/dd)") == "2026/09/27")
        #expect(replacement("::date") == "2026-09-27") // alias

        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let jan31 = cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        #expect(replacement("::tomorrow", now: jan31) == "2026-02-01")
    }

    @Test func timestampVariants() {
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(replacement("::timestamp", now: epoch) == "1700000000")
        #expect(replacement("::timestamp(ms)", now: epoch) == "1700000000000")
        #expect(replacement("::unix", now: epoch) == "1700000000")
        #expect(failure("::timestamp(hours)")?.gutterMessage.contains("timestamp(ms)") == true)
    }

    @Test func timeInsertsClock() {
        let value = replacement("::time")
        #expect(value?.count == 8)
        #expect(value?.contains(":") == true)
    }

    @Test func uuidInsertsID() {
        let edit = SlashCommand.run(name: "uuid", tokenRange: 0..<6, fullText: "::uuid", selection: nil)
        #expect(edit?.replacement.count == 36)
        let upper = replacement("::uuid(upper)")
        #expect(upper == upper?.uppercased())
        #expect(upper.flatMap { UUID(uuidString: $0) } != nil)
        #expect(failure("::uuid(sideways)") != nil)
    }

    // MARK: Random

    @Test func randomBounds() {
        #expect(replacement("::random(5, 5)") == "5")
        #expect(replacement("::random(1)") == "1")
        for _ in 0..<25 {
            let value = replacement("::random(3, 7)").flatMap { Int($0) }
            #expect(value != nil && (3...7).contains(value!))
            let pick = replacement("::random")
            #expect(pick.flatMap { Int($0) }.map { (1...100).contains($0) } == true)
        }
    }

    @Test func randomPickAndErrors() {
        #expect(["red", "blue"].contains(replacement("::random(red, blue)") ?? ""))
        #expect(replacement("::random(0.5, 0.5)") == "0.5")
        #expect(failure("::random(10, 1)")?.gutterMessage.contains("greater than max") == true)
        #expect(failure("::random(0)") != nil)
        #expect(failure("::random(foo)") != nil)
        #expect(failure("::random(1, foo)") != nil)
    }

    // MARK: Line transforms

    @Test func sortLinesWholeBody() {
        let edit = SlashCommand.run(name: "sort_lines", tokenRange: nil, fullText: "b\na\nc", selection: nil)
        #expect(edit?.fullText == "a\nb\nc")
    }

    @Test func sortLinesKeepsTriggerPinned() {
        let edit = SlashCommand.run(name: "sort_lines", tokenRange: nil, fullText: "list\nb\na", selection: nil)
        #expect(edit?.fullText == "list\na\nb")
    }

    @Test func sortDescendingAndTokenLineRemoved() {
        let desc = try? runToken("::sort_lines(desc)", in: "b\na\nc\n").get()
        #expect(desc?.fullText == "c\nb\na")
        // Token alone on its own line is consumed, not sorted into the body.
        let mid = try? runToken("::sort_lines", in: "b\n::sort_lines\na").get()
        #expect(mid?.fullText == "a\nb")
        #expect(failure("::sort_lines(sideways)") != nil)
    }

    @Test func sortSelectionOnly() {
        let edit = SlashCommand.run(name: "sort_lines", tokenRange: nil, fullText: "z\nb\na\ny", selection: 2..<5)
        #expect(edit?.fullText == "z\na\nb\ny")
    }

    @Test func reverseDedupeTrimBlankLines() {
        let reversed = try? runToken("::reverse_lines", in: "list\na\nb\n").get()
        #expect(reversed?.fullText == "list\nb\na")

        let deduped = SlashCommand.run(name: "dedupe_lines", tokenRange: nil, fullText: "a\nb\na\nB", selection: nil)
        #expect(deduped?.fullText == "a\nb\nB")
        let dedupedCI = try? runToken("::dedupe_lines(ci)", in: "a\nA\nb\n").get()
        #expect(dedupedCI?.fullText == "a\nb")

        let trimmed = SlashCommand.run(name: "trim_lines", tokenRange: nil, fullText: "  a  \n\t b\t", selection: nil)
        #expect(trimmed?.fullText == "a\nb")

        let compact = SlashCommand.run(name: "remove_blank_lines", tokenRange: nil, fullText: "a\n\n  \nb", selection: nil)
        #expect(compact?.fullText == "a\nb")
    }

    @Test func shuffleKeepsSameLinesAndTrigger() {
        let edit = SlashCommand.run(name: "shuffle_lines", tokenRange: nil, fullText: "list\na\nb\nc\nd", selection: nil)
        let lines = edit?.fullText?.components(separatedBy: "\n") ?? []
        #expect(lines.first == "list")
        #expect(Set(lines) == Set(["list", "a", "b", "c", "d"]))
        #expect(lines.count == 5)
    }

    // MARK: Text transforms

    @Test func caseTransforms() {
        #expect(replacement("::upper(hello, World)") == "HELLO, WORLD")
        #expect(replacement("::lower(HeLLo)") == "hello")
        #expect(replacement("::title(hELLO wORLD-foo)") == "Hello World-Foo")
        #expect(replacement(#"::trim("  hi  ")"#) == "hi")
    }

    @Test func caseTransformsWholeBufferAndSelection() {
        let whole = SlashCommand.run(name: "upper", tokenRange: nil, fullText: "ab\ncd", selection: nil)
        #expect(whole?.fullText == "AB\nCD")
        let selected = SlashCommand.run(name: "upper", tokenRange: nil, fullText: "say hi there", selection: 4..<6)
        #expect(selected?.fullText == "say HI there")
        // Trigger line stays readable when transforming the body.
        let triggered = SlashCommand.run(name: "upper", tokenRange: nil, fullText: "code\nlet x", selection: nil)
        #expect(triggered?.fullText == "code\nLET X")
    }

    @Test func base64RoundTripAndErrors() {
        #expect(replacement("::base64_encode(hello)") == "aGVsbG8=")
        #expect(replacement("::base64_decode(aGVsbG8=)") == "hello")
        #expect(failure("::base64_decode(not!base64!)")?.gutterMessage.contains("not valid UTF-8 base64") == true)
        #expect(failure("::base64_encode", in: "body text ")?.gutterMessage.contains("needs text") == true)
    }

    @Test func hashes() {
        #expect(replacement("::hash(abc)") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(replacement("::sha256(abc)") == replacement("::hash(abc)"))
        #expect(replacement("::md5(abc)") == "900150983cd24fb0d6963f7d28e17f72")
        #expect(failure("::hash", in: "body ")?.gutterMessage.contains("needs text") == true)
    }

    @Test func jsonFormatArgBufferAndErrors() {
        let pretty = replacement(#"::json_format({"b":1,"a":[1,2]})"#) ?? ""
        #expect(pretty.contains("\"a\""))
        #expect(pretty.range(of: "\"a\"")!.lowerBound < pretty.range(of: "\"b\"")!.lowerBound)

        let whole = try? runToken("::json_format", in: "{\"a\":1}\n::json_format").get()
        #expect(whole?.fullText?.contains("\"a\"") == true)
        #expect(whole?.fullText?.contains("::json_format") == false)

        #expect(failure("::json_format({nope)")?.gutterMessage.contains("invalid JSON") == true)
    }

    // MARK: Count + help

    @Test func countVariants() {
        let whole = SlashCommand.run(name: "count", tokenRange: nil, fullText: "one two\nthree", selection: nil)
        #expect(whole?.replacement == "2 lines · 3 words · 13 chars")
        #expect(replacement("::count(words)", in: "one two\nthree ") == "3")
        #expect(replacement("::count(some text here)") == "1 lines · 3 words · 14 chars")
        // Blank + `//` lines are ignored, like NoteStats everywhere else.
        let skipped = SlashCommand.run(name: "count", tokenRange: nil, fullText: "a\n// note\n\nb", selection: nil)
        #expect(skipped?.replacement == "2 lines · 2 words · 3 chars")
        // The token itself is not counted.
        #expect(replacement("::count") == "0 lines · 0 words · 0 chars")
    }

    @Test func helpListsAndExplains() {
        let all = replacement("::help") ?? ""
        #expect(all.contains("::today"))
        #expect(all.contains("::json_format"))
        #expect(replacement("::help(sort_lines)")?.contains("Sort lines") == true)
        #expect(failure("::help(bogus)") != nil)
    }

    // MARK: Diagnostics / gutter

    @Test func diagnosticsFlagUnknownOnly() {
        let text = "ok ::today\nbad ::tday here\n::tod still typing\nstd::thing"
        let diags = SlashCommand.diagnostics(in: text)
        #expect(diags.count == 1)
        #expect(diags.first?.line == 1)
        #expect(diags.first?.message.contains("did you mean ::today") == true)

        let gutter = SlashCommand.gutterLines(in: text)
        #expect(gutter.count == 4)
        #expect(gutter[0] == "")
        #expect(!gutter[1].isEmpty)
        #expect(gutter[2] == "")
        #expect(gutter[3] == "")
    }

    @Test func diagnosticsKnowExtensionAndAliasNames() {
        let ext = JSExtension.Script(fileName: "shout.js", commandName: "shout", hint: "h", source: "")
        #expect(SlashCommand.diagnostics(in: "::shout ::date", extensions: [ext]).isEmpty)
        #expect(SlashCommand.diagnostics(in: "::shout").count == 1)
    }
}
