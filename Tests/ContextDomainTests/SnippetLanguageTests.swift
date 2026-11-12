import Foundation
import Testing
@testable import ContextDomain

struct SnippetLanguageTests {
    @Test func roles() {
        for language in CodeHighlight.Language.allCases {
            let text = "Widget value call() # comment"
            let tokens = CodeHighlight.tokens(in: text, language: language)
            #expect(tokens.contains { $0.kind == .function && text[$0.range] == "call" })
            #expect(tokens.contains { $0.kind == .identifier && text[$0.range] == "value" })
            if language != .shell {
                #expect(tokens.contains { $0.kind == .type && text[$0.range] == "Widget" })
            }
        }
    }

    @Test func persistedFenceChoice() throws {
        let note = ContextNote(text: "code\nlet value = 1")
        let text = CodeHighlight.choosing(.python, in: note, caret: 0)
        let restored = try JSONDecoder().decode(ContextNote.self, from: JSONEncoder().encode(ContextNote(text: text)))
        #expect(CodeHighlight.blocks(for: restored).first?.language == .python)
        #expect(text.contains("let value = 1"))
    }

    @Test func activeBlockOnly() {
        let text = "```swift\nA()\n```\n```python\nb()\n```"
        let caret = (text as NSString).range(of: "b()").location
        let result = CodeHighlight.choosing(.javascript, in: ContextNote(text: text), caret: caret)
        #expect(result == "```swift\nA()\n```\n```javascript\nb()\n```")
        #expect(CodeHighlight.choosing(.shell, in: ContextNote(text: text), caret: 0) == text)
    }
}
