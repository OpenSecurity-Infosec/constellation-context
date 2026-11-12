import Foundation
import Testing
@testable import ContextDomain

struct NoteTemplateTests {
    @Test func expandsDateWithoutChangingMarkdown() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        let date = Date(timeIntervalSince1970: 0)
        #expect(NoteTemplate.expand("---\ncustom: keep\n---\n# {{date}}\n[[link]] ![[image]] {{unknown}}\n{{date}}", at: date, timeZone: zone)
            == "---\ncustom: keep\n---\n# 1970-01-01\n[[link]] ![[image]] {{unknown}}\n1970-01-01")
    }

    @Test func usesExplicitLocalDay() throws {
        let zone = try #require(TimeZone(secondsFromGMT: -3600))
        #expect(NoteTemplate.expand("{{date}}", at: Date(timeIntervalSince1970: 0), timeZone: zone) == "1969-12-31")
    }
}
