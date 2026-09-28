import ContextDomain
import Testing

@Suite struct ChecklistParityTests {
    @Test func parseMarkerRows() {
        let items = ChecklistItem.parse("list\n[ ] milk\n- eggs\n1. bread")
        #expect(items.count == 3)
        #expect(items[0].marker == .checkbox)
        #expect(items[1].marker == .bullet)
        #expect(items[1].text == "eggs")
        #expect(items[2].text == "bread")
    }

    @Test func parseMarkerRowsWithoutTrigger() {
        let items = ChecklistItem.parse("[ ] milk\n- eggs")
        #expect(items.count == 2)
        #expect(items[0].marker == .checkbox)
        #expect(items[1].marker == .bullet)
    }

    @Test func tabNestsAndShiftTabOutdents() {
        let nested = ChecklistItem.indent(text: "list\n[ ] milk", id: 0, direction: .in)
        #expect(nested == "list\n  [ ] milk")
        let items = ChecklistItem.parse(nested)
        #expect(items.first?.indent == 1)
        let out = ChecklistItem.indent(text: nested, id: 0, direction: .out)
        #expect(out == "list\n[ ] milk")
    }

    @Test func outdentFloorsAtZero() {
        let out = ChecklistItem.indent(text: "list\n[ ] milk", id: 0, direction: .out)
        #expect(out == "list\n[ ] milk")
    }

    @Test func cycleCheckboxToBulletToNumbered() {
        let start = "list\n[ ] milk"
        let bullet = ChecklistItem.cycleMarker(text: start, id: 0)
        #expect(bullet == "list\n- milk")
        let numbered = ChecklistItem.cycleMarker(text: bullet, id: 0)
        #expect(numbered == "list\n1. milk")
        let back = ChecklistItem.cycleMarker(text: numbered, id: 0)
        #expect(back == "list\n[ ] milk")
    }

    @Test func cyclePreservesIndent() {
        let out = ChecklistItem.cycleMarker(text: "list\n  [ ] milk", id: 0)
        #expect(out == "list\n  - milk")
    }

    @Test func serializeRoundTripsMarkers() {
        let text = "list\n[ ] milk\n- eggs\n1. bread"
        let items = ChecklistItem.parse(text)
        #expect(ChecklistItem.serialize(items, trigger: true) == text)
    }

    @Test func moveReordersLines() {
        let text = "list\n[ ] milk\n- eggs\n1. bread"
        #expect(ChecklistItem.move(text: text, from: 0, to: 2) == "list\n- eggs\n1. bread\n[ ] milk")
    }

    @Test func moveUpReordersLines() {
        let text = "list\n[ ] milk\n- eggs\n1. bread"
        #expect(ChecklistItem.move(text: text, from: 2, to: 0) == "list\n1. bread\n[ ] milk\n- eggs")
    }

    @Test func moveKeepsTickNestAndMarkers() {
        let text = "list\n[x] done\n  - nested\n2. second"
        let moved = ChecklistItem.move(text: text, from: 1, to: 0)
        #expect(moved == "list\n  - nested\n[x] done\n2. second")
        let items = ChecklistItem.parse(moved)
        #expect(items[0].indent == 1 && items[0].marker == .bullet)
        #expect(items[1].checked)
        #expect(items[2].marker == .numbered(2))
    }

    @Test func moveWithoutTrigger() {
        #expect(ChecklistItem.move(text: "[ ] a\n[ ] b", from: 1, to: 0) == "[ ] b\n[ ] a")
    }

    @Test func moveSameSpotIsNoop() {
        let text = "list\n[ ] a\n[ ] b"
        #expect(ChecklistItem.move(text: text, from: 1, to: 1) == text)
    }

    @Test func moveOutOfRangeIsNoop() {
        let text = "list\n[ ] a"
        #expect(ChecklistItem.move(text: text, from: 9, to: 0) == text)
    }
}
