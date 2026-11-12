import ContextDomain
import Testing

@Suite struct PasteCollectionTests {
    @Test func appendFirstItemToBareTrigger() {
        let next = PasteCollection.appending("hello", to: "paste")
        #expect(next == "paste\n\nhello")
        #expect(PasteCollection.items(in: next) == ["hello"])
    }

    @Test func eachPasteIsASeparateDelimitedItem() {
        var text = PasteCollection.appending("alpha", to: "paste")
        text = PasteCollection.appending("beta line1\nbeta line2", to: text)
        text = PasteCollection.appending("gamma", to: text)
        #expect(text == "paste\n\nalpha\n---\nbeta line1\nbeta line2\n---\ngamma")
        #expect(PasteCollection.items(in: text) == ["alpha", "beta line1\nbeta line2", "gamma"])
    }

    @Test func appendSanitizesLikeAnyPaste() {
        // Reuses PlainText.sanitizePasteboard: bullets stripped, CRLF folded.
        let next = PasteCollection.appending("- milk\r\n• eggs", to: "paste")
        #expect(PasteCollection.items(in: next) == ["milk\neggs"])
    }

    @Test func emptyAppendIsNoOp() {
        let text = PasteCollection.appending("alpha", to: "paste")
        #expect(PasteCollection.appending("", to: text) == text)
        #expect(PasteCollection.appending("  \n\n ", to: text) == text)
    }

    @Test func consecutiveDuplicateIsNoOpButLaterRepeatIsKept() {
        var text = PasteCollection.appending("alpha", to: "paste")
        text = PasteCollection.appending("alpha", to: text)
        #expect(PasteCollection.items(in: text) == ["alpha"])
        text = PasteCollection.appending("beta", to: text)
        text = PasteCollection.appending("alpha", to: text)
        #expect(PasteCollection.items(in: text) == ["alpha", "beta", "alpha"])
    }

    @Test func bareDelimiterLineInsideAPasteCannotSplitIt() {
        // sanitize drops bare "---" lines (markdown table junk), so a
        // collected item can never forge the item delimiter.
        let text = PasteCollection.appending("top\n---\nbottom", to: "paste")
        #expect(PasteCollection.items(in: text) == ["top\nbottom"])
    }

    @Test func delimiterNeedsItsOwnLine() {
        let text = "paste\n\na --- b\n----\nstill same"
        #expect(PasteCollection.items(in: text) == ["a --- b\n----\nstill same"])
        #expect(PasteCollection.items(in: "paste\n\none\n  ---  \ntwo") == ["one", "two"])
    }

    @Test func legacyUndelimitedBodyIsOneItem() {
        // Paste notes collected before delimiters existed keep their
        // boundaries unknowable; the whole body reads as a single item and
        // the next append starts delimiting from there.
        let legacy = "paste\nfirst old\nsecond old"
        #expect(PasteCollection.items(in: legacy) == ["first old\nsecond old"])
        let next = PasteCollection.appending("new", to: legacy)
        #expect(PasteCollection.items(in: next) == ["first old\nsecond old", "new"])
    }

    @Test func noItemsInEmptyOrBareTrigger() {
        #expect(PasteCollection.items(in: "").isEmpty)
        #expect(PasteCollection.items(in: "paste").isEmpty)
        #expect(PasteCollection.items(in: "paste\n\n").isEmpty)
    }

    @Test func joinedIsTheCopyAllPayload() {
        var text = PasteCollection.appending("alpha", to: "paste")
        text = PasteCollection.appending("beta", to: text)
        #expect(PasteCollection.joined(text) == "alpha\n\nbeta")
        #expect(PasteCollection.joined(text, separator: "\n") == "alpha\nbeta")
        #expect(PasteCollection.joined("paste") == "")
    }

    @Test func copyingAllDoesNotRecollectItself() {
        // Copy-all writes the joined payload to the pasteboard; if the
        // monitor still delivers it, appending must recognize it.
        var text = PasteCollection.appending("alpha", to: "paste")
        text = PasteCollection.appending("beta", to: text)
        let payload = PasteCollection.joined(text)
        #expect(PasteCollection.appending(payload, to: text) == text)
    }

    @Test func clearedKeepsTheMode() {
        let text = PasteCollection.appending("alpha", to: "paste")
        #expect(PasteCollection.cleared(text) == "paste")
        #expect(ContextNote(text: PasteCollection.cleared(text)).kind == .paste)
        #expect(PasteCollection.cleared("plain note") == "")
    }

    @Test func removingLastItem() {
        var text = PasteCollection.appending("alpha", to: "paste")
        text = PasteCollection.appending("beta", to: text)
        text = PasteCollection.removingLastItem(from: text)
        #expect(PasteCollection.items(in: text) == ["alpha"])
        text = PasteCollection.removingLastItem(from: text)
        #expect(text == "paste")
        #expect(PasteCollection.removingLastItem(from: text) == "paste")
    }

    @Test func serializeRoundTrips() {
        let items = ["one", "two\nlines", "three"]
        let text = PasteCollection.serialize(items: items, trigger: true)
        #expect(PasteCollection.items(in: text) == items)
        #expect(PasteCollection.serialize(items: [], trigger: true) == "paste")
        #expect(PasteCollection.serialize(items: ["x"], trigger: false) == "x")
    }

    @Test func statusLineCountsItems() {
        #expect(PasteCollection.statusLine(itemCount: 0, armed: false) == "Type paste + Return to collect copies.")
        #expect(PasteCollection.statusLine(itemCount: 0, armed: true) == "Collecting — everything you copy lands here as its own item.")
        #expect(PasteCollection.statusLine(itemCount: 1, armed: true) == "1 paste collected · ⌘⇧C copies it")
        #expect(PasteCollection.statusLine(itemCount: 3, armed: true) == "3 pastes collected · ⌘⇧C copies all joined")
    }
}
