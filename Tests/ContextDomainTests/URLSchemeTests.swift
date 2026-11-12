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

@Suite struct URLSchemeEdgeTests {
    @Test func decoding() {
        #expect(URLScheme.parse(URL(string: "context://new?text=%E9%9B%AA%20%F0%9F%98%80%26%25%2B")!) == .newNote(text: "雪 😀&%+"))
        #expect(URLScheme.parse(URL(string: "context://new?text=%2520")!) == .newNote(text: "%20"))
        #expect(URLScheme.parse(URL(string: "context://new?text=")!) == .newNote(text: ""))
        #expect(URLScheme.parse(URL(string: "context://search?query=")!) == .search(query: ""))
    }
    @Test(arguments: ["context://append?text=", "context://open?id=missing", "context://new?text=a&text=b", "context://open/unknown", "context://open#fragment", "context://new?text", "context://search", "context://append"])
    func invalid(value: String) {
        #expect(URLScheme.parse(URL(string: value)!) == nil)
    }
}
