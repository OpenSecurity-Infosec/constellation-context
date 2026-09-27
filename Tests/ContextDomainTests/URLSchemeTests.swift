import ContextDomain
import Foundation
import Testing

@Suite struct URLSchemeTests {
    @Test func openParses() {
        #expect(URLScheme.parse(URL(string: "context://open")!) == .open)
    }

    @Test func newWithText() {
        let intent = URLScheme.parse(URL(string: "context://new?text=hello%20world")!)
        #expect(intent == .newNote(text: "hello world"))
    }

    @Test func newWithoutText() {
        #expect(URLScheme.parse(URL(string: "context://new")!) == .newNote(text: nil))
    }

    @Test func searchNeedsQuery() {
        #expect(URLScheme.parse(URL(string: "context://search?query=milk")!) == .search(query: "milk"))
        #expect(URLScheme.parse(URL(string: "context://search")!) == nil)
    }

    @Test func appendNeedsText() {
        #expect(URLScheme.parse(URL(string: "context://append?text=more")!) == .append(text: "more"))
        #expect(URLScheme.parse(URL(string: "context://append")!) == nil)
    }

    @Test func rejectsOtherSchemes() {
        #expect(URLScheme.parse(URL(string: "https://example.com")!) == nil)
        #expect(URLScheme.parse(URL(string: "context://bogus")!) == nil)
    }
}
