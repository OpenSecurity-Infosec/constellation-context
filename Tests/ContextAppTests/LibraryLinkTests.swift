import Testing
@testable import ContextApp

@MainActor
@Suite struct LibraryLinkTests {
    @Test func linksPreserveSourceAndSkipEmbeds() {
        let text = "[[Folder/Note#Heading|Alias]] ![[image.png]]"
        #expect(CanvasReader.wikiTargets(text) == ["Folder/Note#Heading|Alias"])
        let rendered = CanvasReader.linkedMarkdown(text)
        #expect(rendered.contains("[Alias](context-wiki://"))
        #expect(rendered.contains("![[image.png]]"))
        #expect(CanvasReader.linkedMarkdown("ordinary text") == "ordinary text")
    }
}
