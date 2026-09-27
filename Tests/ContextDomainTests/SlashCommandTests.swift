import ContextDomain
import Foundation
import Testing

@Suite struct SlashCommandTests {
    @Test func tokenDetected() {
        let found = SlashCommand.token(at: 8, in: "hello ::tod")
        #expect(found?.token == "::tod")
    }

    @Test func tokenNilWithoutOpener() {
        #expect(SlashCommand.token(at: 5, in: "hello") == nil)
    }

    @Test func completionsFilter() {
        #expect(SlashCommand.completions(matching: "").count == 4)
        #expect(SlashCommand.completions(matching: "to").map(\.name) == ["today"])
        #expect(SlashCommand.completions(matching: "s").map(\.name) == ["sort_lines"])
    }

    @Test func todayInsertsISODate() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = cal.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        let edit = SlashCommand.run(name: "today", tokenRange: 0..<7, fullText: "::today", selection: nil, now: date)
        #expect(edit?.replacement == "2026-09-27")
    }

    @Test func uuidInsertsID() {
        let edit = SlashCommand.run(name: "uuid", tokenRange: 0..<6, fullText: "::uuid", selection: nil)
        #expect(edit?.replacement.count == 36)
    }

    @Test func sortLinesWholeBody() {
        let edit = SlashCommand.run(name: "sort_lines", tokenRange: nil, fullText: "b\na\nc", selection: nil)
        #expect(edit?.fullText == "a\nb\nc")
    }

    @Test func sortLinesKeepsTriggerPinned() {
        let edit = SlashCommand.run(name: "sort_lines", tokenRange: nil, fullText: "list\nb\na", selection: nil)
        #expect(edit?.fullText == "list\na\nb")
    }

    @Test func unknownCommandNil() {
        #expect(SlashCommand.run(name: "nope", tokenRange: nil, fullText: "", selection: nil) == nil)
    }
}
