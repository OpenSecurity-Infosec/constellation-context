import ContextDomain
import Testing

@Suite struct NoteTests {
    @Test func triggerDetection() {
        #expect(ContextNote(text: "math\n1+1").kind == .math)
        #expect(ContextNote(text: "LIST\n- a").kind == .list)
        #expect(ContextNote(text: "hello").kind == .plain)
        #expect(ContextNote(text: "count\n1 2 3").kind == .count)
    }

    @Test func bodyStripsTrigger() {
        #expect(ContextNote(text: "math\n2+2").bodyWithoutTrigger == "2+2")
    }

    @Test func sanitizeStripsBullets() {
        #expect(PlainText.sanitize("- hello") == "hello")
        #expect(PlainText.sanitize("1. hello") == "hello")
        #expect(PlainText.sanitize("  • hello  ") == "hello")
    }

    @Test func statsIgnoreComments() {
        let s = NoteStats.compute(for: "one two\n// skip me\nthree")
        #expect(s.words == 3)
        #expect(s.lines == 2)
    }

    @Test func checklistToggle() {
        let toggled = ChecklistItem.toggle(text: "list\n[ ] milk", id: 0)
        #expect(toggled.contains("[x] milk"))
    }
}
