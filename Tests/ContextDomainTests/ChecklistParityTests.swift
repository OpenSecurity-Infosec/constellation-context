import ContextDomain
import Foundation
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

    @Test func blockMoveParentCarriesChildrenDown() {
        let text = "list\n[ ] inbox\n  [ ] child1\n    [ ] grandchild\n  [ ] child2\n[ ] next"
        let out = ChecklistItem.moveBlock(text: text, from: 0, to: 5, bodyLineCount: 6)
        #expect(out == "list\n[ ] next\n[ ] inbox\n  [ ] child1\n    [ ] grandchild\n  [ ] child2")
    }

    @Test func blockMoveParentCarriesChildrenUp() {
        let text = "list\n[ ] first\n[x] parent\n  - kid\n    1. grandkid\n  - kid2"
        let out = ChecklistItem.moveBlock(text: text, from: 1, to: 0, bodyLineCount: 5)
        #expect(out == "list\n[x] parent\n  - kid\n    1. grandkid\n  - kid2\n[ ] first")
        let items = ChecklistItem.parse(out)
        #expect(items[0].checked)
        #expect(items[1].marker == .bullet && items[1].indent == 1)
        #expect(items[2].marker == .numbered(1) && items[2].indent == 2)
        #expect(items[3].marker == .bullet && items[3].indent == 1)
    }

    @Test func blockMoveLeafIsSingleLine() {
        let text = "list\n[ ] a\n  [ ] child\n[ ] b"
        let out = ChecklistItem.moveBlock(text: text, from: 2, to: 0, bodyLineCount: 3)
        #expect(out == "list\n[ ] b\n[ ] a\n  [ ] child")
    }

    @Test func blockMoveIntoOwnBlockIsNoop() {
        let text = "list\n[ ] parent\n  [ ] child\n[ ] after"
        #expect(ChecklistItem.moveBlock(text: text, from: 0, to: 1, bodyLineCount: 3) == text)
        #expect(ChecklistItem.moveBlock(text: text, from: 0, to: 2, bodyLineCount: 3) == text)
    }

    @Test func blockMoveHomeIsNoop() {
        let text = "list\n[ ] parent\n  [ ] child\n[ ] after"
        #expect(ChecklistItem.moveBlock(text: text, from: 1, to: 2, bodyLineCount: 3) == text)
    }

    @Test func moveDisplayTranslates() {
        // Display [0,1,2], drag row 0 past the end → anchor is bodyLineCount.
        #expect(ChecklistItem.moveDisplay(ids: [0, 1, 2], from: IndexSet(integer: 0), to: 3, bodyLineCount: 3) == (0, 3))
        // Drag row 2 to the top → anchor is the first row's id.
        #expect(ChecklistItem.moveDisplay(ids: [0, 1, 2], from: IndexSet(integer: 2), to: 0, bodyLineCount: 3) == (2, 0))
        // Drag row 0 before row 2 → anchor is row 2's id.
        #expect(ChecklistItem.moveDisplay(ids: [0, 1, 2], from: IndexSet(integer: 0), to: 1, bodyLineCount: 3) == (0, 2))
    }

    @Test func blockMoveDisplayRoundTrip() {
        let text = "list\n[ ] parent\n  [ ] child\n[ ] after"
        let ids = ChecklistItem.parse(text).map(\.id)
        let (src, anchor) = ChecklistItem.moveDisplay(ids: ids, from: IndexSet(integer: 0), to: 3, bodyLineCount: 3)
        #expect(ChecklistItem.moveBlock(text: text, from: src, to: anchor, bodyLineCount: 3)
            == "list\n[ ] after\n[ ] parent\n  [ ] child")
    }
}
