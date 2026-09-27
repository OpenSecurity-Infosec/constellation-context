import ContextDomain
import Testing

@Suite struct LinkShrinkTests {
    @Test func shortURLsUntouched() {
        #expect(LinkShrink.shortened("https://example.com/a") == "example.com/a")
    }

    @Test func longURLKeepsReadableEnding() {
        let full = "https://example.com/docs/2024/09/very-long-article-slug-about-notes"
        let short = LinkShrink.shortened(full)
        #expect(short.count <= LinkShrink.maxVisible)
        #expect(short.contains("…"))
        #expect(short.hasSuffix("about-notes"))
        #expect(short.hasPrefix("example.com/docs"))
    }

    @Test func urlRangesFound() {
        let ranges = LinkShrink.urlRanges(in: "see https://example.com/a and www.test.org/b.")
        #expect(ranges.count == 2)
    }

    @Test func expandMatchesTail() {
        let full = "https://example.com/docs/very-long-article-slug-about-notes"
        let display = LinkShrink.shortened(full)
        #expect(LinkShrink.expand(display: display, candidates: [full]) == full)
    }

    @Test func openableAddsScheme() {
        #expect(LinkShrink.openableURL("example.com/a")?.absoluteString == "https://example.com/a")
        #expect(LinkShrink.openableURL("https://example.com/a")?.absoluteString == "https://example.com/a")
    }
}
