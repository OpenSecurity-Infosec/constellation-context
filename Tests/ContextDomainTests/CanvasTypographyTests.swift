import ContextDomain
import Foundation
import Testing

@Suite struct CanvasTypographyTests {
    @Test func aProseNotesFirstLineIsItsTitle() {
        let text = "Q3 planning\nconfirm scope\nship it"
        let range = CanvasTypography.titleRange(in: text)
        #expect(range == NSRange(location: 0, length: 12), "the title includes its line break")
        #expect(CanvasTypography.titleRange(in: "Just one line") == NSRange(location: 0, length: 13))
    }

    @Test func legacyWordsAreProseAndBlankFirstLinesGetNoTitle() {
        #expect(CanvasTypography.titleRange(in: "math\n2 + 2") == NSRange(location: 0, length: 5))
        #expect(CanvasTypography.titleRange(in: "List\n- a") == NSRange(location: 0, length: 5))
        #expect(CanvasTypography.titleRange(in: "\nbody only") == nil)
        #expect(CanvasTypography.titleRange(in: "   \nbody") == nil)
        #expect(CanvasTypography.titleRange(in: "") == nil)
        #expect(CanvasTypography.isProse("sum\n1\n2"))
        #expect(CanvasTypography.isProse("mathematics is fun"))
    }
}
