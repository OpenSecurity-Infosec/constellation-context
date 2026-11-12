import ContextDomain
import Foundation
import Testing

@Suite struct ModeConsolidationTests {
    @Test func legacyWordsAndPersistedMetadataAreInert() throws {
        for word in ["math", "sum", "avg", "average", "count", "list", "code", "timer", "paste"] {
            let original = ContextNote(text: word + "\n[[link]] ![[embed]]\n- [ ] task")
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ContextNote.self, from: data)
            #expect(decoded == original)
            #expect(decoded.kind == .plain)
            #expect(decoded.bodyWithoutTrigger == original.text)
        }
        #expect(!SlashCommand.builtins.contains { $0.name == "paste" })
    }

    @Test func commandsProducePortableMarkdown() {
        #expect(SlashCommand.run(name: "list", tokenRange: 14..<20, fullText: "apple\n- [x] b\n::list", selection: nil)?.fullText == "- [ ] apple\n- [x] b")
        let input = "```\n[[link]]\n::code"
        let start = input.count - 6
        let edit = SlashCommand.run(name: "code", tokenRange: start..<input.count, fullText: input, selection: nil)
        #expect(edit?.fullText == "````\n```\n[[link]]\n````")
        #expect(SlashCommand.run(name: "count", tokenRange: 8..<15, fullText: "one two\n::count", selection: nil)?.replacement == "1 lines · 2 words · 7 chars")
    }
}
