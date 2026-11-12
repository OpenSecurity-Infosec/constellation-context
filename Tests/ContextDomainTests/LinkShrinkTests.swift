import ContextDomain
import Testing

@Suite struct LinkShrinkTests {
    private func raws(in text: String) -> [String] {
        LinkShrink.urlRanges(in: text).map { String(text[$0]) }
    }

    // MARK: - Shortening

    @Test func shortURLsUntouched() {
        #expect(LinkShrink.shortened("https://example.com/a") == "example.com/a")
    }

    @Test func shortenedStripsSchemeCaseInsensitively() {
        #expect(LinkShrink.shortened("HTTPS://Example.COM/A") == "Example.COM/A")
        #expect(LinkShrink.shortened("http://example.com/a/") == "example.com/a")
    }

    @Test func longURLKeepsReadableEnding() {
        let full = "https://example.com/docs/2024/09/very-long-article-slug-about-notes"
        let short = LinkShrink.shortened(full)
        #expect(short.count <= LinkShrink.maxVisible)
        #expect(short.contains("…"))
        #expect(short.hasSuffix("about-notes"))
        #expect(short.hasPrefix("example.com/docs"))
    }

    @Test func shortenedBoundaryAtMaxVisible() {
        let exact = "example.com/" + String(repeating: "a", count: 36) // 48 chars
        #expect(exact.count == LinkShrink.maxVisible)
        #expect(LinkShrink.shortened("https://" + exact) == exact)
        let over = exact + "a"
        let short = LinkShrink.shortened("https://" + over)
        #expect(short.count <= LinkShrink.maxVisible)
        #expect(short.contains("…"))
    }

    @Test func shortenedNonHttpKeepsSchemeAndShrinksMiddle() {
        let full = "ftp://files.example.com/pub/releases/2024/very-long-file-name-here.zip"
        let short = LinkShrink.shortened(full)
        #expect(short.hasPrefix("ftp://"))
        #expect(short.count <= LinkShrink.maxVisible)
        #expect(short.hasSuffix(".zip"))
        #expect(LinkShrink.shortened("mailto:hi@example.com") == "hi@example.com")
    }

    // MARK: - Detection

    @Test func urlRangesFound() {
        let ranges = LinkShrink.urlRanges(in: "see https://example.com/a and www.test.org/b.")
        #expect(ranges.count == 2)
        #expect(raws(in: "see https://example.com/a and www.test.org/b.")
            == ["https://example.com/a", "www.test.org/b"])
    }

    @Test func trailingPunctuationExcluded() {
        let text = "See https://example.com/a, then (https://example.com/b). End https://example.com/c!"
        #expect(raws(in: text) == ["https://example.com/a", "https://example.com/b", "https://example.com/c"])
        #expect(raws(in: "really? https://example.com/d; yes: https://example.com/e:")
            == ["https://example.com/d", "https://example.com/e"])
    }

    @Test func balancedParenthesesKeptUnbalancedDropped() {
        let wiki = "https://en.wikipedia.org/wiki/Note_(software)"
        #expect(raws(in: "read \(wiki) today") == [wiki])
        #expect(raws(in: "(see \(wiki))") == [wiki])
        #expect(raws(in: "[docs](https://example.com/guide)") == ["https://example.com/guide"])
    }

    @Test func quotedAndAngleBracketedURLsAreClean() {
        #expect(raws(in: "\"https://example.com/quoted\"") == ["https://example.com/quoted"])
        #expect(raws(in: "<https://example.com/angle>") == ["https://example.com/angle"])
    }

    @Test func multipleLinksPerLineWithQueryAndFragment() {
        let text = "a https://example.com/s?q=tea&p=2 b example.org/x#top c www.test.io/y"
        #expect(raws(in: text) == [
            "https://example.com/s?q=tea&p=2",
            "example.org/x#top",
            "www.test.io/y",
        ])
    }

    @Test func nonHttpSchemesDetected() {
        let text = "ftp://files.example.com/pub/a.txt mailto:hi@example.com "
            + "context://search?query=milk obsidian://open?vault=Notes&file=Todo"
        #expect(raws(in: text) == [
            "ftp://files.example.com/pub/a.txt",
            "mailto:hi@example.com",
            "context://search?query=milk",
            "obsidian://open?vault=Notes&file=Todo",
        ])
    }

    @Test func bareEmailIsOneMailtoLinkNotDomainLink() {
        let text = "write to hi@example.com please"
        #expect(raws(in: text) == ["hi@example.com"])
        #expect(LinkShrink.openableURL("hi@example.com")?.absoluteString == "mailto:hi@example.com")
    }

    @Test func bareDomainPortPathQueryFragmentKept() {
        #expect(raws(in: "hit example.com:8080/x?q=1#top now") == ["example.com:8080/x?q=1#top"])
        #expect(LinkShrink.openableURL("example.com:8080/x?q=1#top")?.absoluteString
            == "https://example.com:8080/x?q=1#top")
    }

    @Test func localhostAndIPv4AreHTTP() {
        #expect(raws(in: "dev localhost:3000/dash") == ["localhost:3000/dash"])
        #expect(LinkShrink.openableURL("localhost:3000/dash")?.absoluteString == "http://localhost:3000/dash")
        #expect(raws(in: "pi 192.168.1.20:8080/status") == ["192.168.1.20:8080/status"])
        #expect(LinkShrink.openableURL("192.168.1.20:8080/status")?.absoluteString
            == "http://192.168.1.20:8080/status")
    }

    @Test func plainTextIsNotLinkified() {
        #expect(raws(in: "notes.txt and README.md and version 1.2.3 and e.g. this").isEmpty)
        #expect(raws(in: "Hello.World is a sentence, not a site").isEmpty)
        #expect(raws(in: "no links here at all").isEmpty)
    }

    @Test func unicodePathKept() {
        #expect(raws(in: "menu https://example.com/café/menu end")
            == ["https://example.com/café/menu"])
    }

    @Test func linksCarryRawDisplayAndShortenedFlag() {
        let long = "https://example.com/docs/2024/09/very-long-article-slug-about-notes"
        let links = LinkShrink.links(in: "x \(long) y https://example.com/a z")
        #expect(links.count == 2)
        #expect(links[0].raw == long)
        #expect(links[0].display == LinkShrink.shortened(long))
        #expect(links[0].isShortened)
        #expect(links[0].url?.absoluteString == long)
        #expect(links[1].raw == "https://example.com/a")
        #expect(!links[1].isShortened)
    }

    // MARK: - Expand / openable

    @Test func expandMatchesTail() {
        let full = "https://example.com/docs/very-long-article-slug-about-notes"
        let display = LinkShrink.shortened(full)
        #expect(LinkShrink.expand(display: display, candidates: [full]) == full)
    }

    @Test func expandHandlesTrailingSlashCandidate() {
        let full = "https://example.com/docs/very-long-article-slug-about-notes/"
        let display = LinkShrink.shortened(full)
        #expect(LinkShrink.expand(display: display, candidates: [full]) == full)
    }

    @Test func expandRejectsUnknownDisplays() {
        let full = "https://example.com/docs/very-long-article-slug-about-notes"
        #expect(LinkShrink.expand(display: "other.com/…nope", candidates: [full]) == nil)
        #expect(LinkShrink.expand(display: "example.com/plain", candidates: [full]) == nil)
        #expect(LinkShrink.expand(display: full, candidates: [full]) == full)
    }

    @Test func openableAddsScheme() {
        #expect(LinkShrink.openableURL("example.com/a")?.absoluteString == "https://example.com/a")
        #expect(LinkShrink.openableURL("https://example.com/a")?.absoluteString == "https://example.com/a")
    }

    @Test func openablePreservesNonHttpSchemes() {
        #expect(LinkShrink.openableURL("ftp://files.example.com/a")?.scheme == "ftp")
        #expect(LinkShrink.openableURL("mailto:hi@example.com")?.scheme == "mailto")
        #expect(LinkShrink.openableURL("context://search?query=milk")?.scheme == "context")
    }

    @Test func openableRejectsJunkAndShortenedDisplays() {
        #expect(LinkShrink.openableURL("") == nil)
        #expect(LinkShrink.openableURL("   ") == nil)
        #expect(LinkShrink.openableURL("not a url") == nil)
        let display = LinkShrink.shortened("https://example.com/docs/very-long-article-slug-about-notes")
        #expect(LinkShrink.openableURL(display) == nil)
        #expect(LinkShrink.openableURL("example.com/a.")?.absoluteString == "https://example.com/a")
    }

    // MARK: - Caret lookup (⌘↩)

    @Test func linkAtCaretBoundaries() {
        let text = "go https://example.com/abc now" // link UTF-16 range 3..<26
        #expect(LinkShrink.link(atUTF16Offset: 3, in: text)?.raw == "https://example.com/abc")
        #expect(LinkShrink.link(atUTF16Offset: 25, in: text)?.raw == "https://example.com/abc")
        #expect(LinkShrink.link(atUTF16Offset: 26, in: text)?.raw == "https://example.com/abc") // caret at end
        #expect(LinkShrink.link(atUTF16Offset: 27, in: text) == nil)
        #expect(LinkShrink.link(atUTF16Offset: 2, in: text) == nil)
        #expect(LinkShrink.link(atUTF16Offset: -1, in: text) == nil)
    }

    @Test func linkAtCaretUsesUTF16Offsets() {
        let text = "😀 https://example.com/a" // emoji is 2 UTF-16 units, link starts at 3
        #expect(LinkShrink.link(atUTF16Offset: 3, in: text)?.raw == "https://example.com/a")
    }
}
