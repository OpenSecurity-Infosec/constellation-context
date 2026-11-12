import ContextDomain
import Foundation
import Testing

@Suite struct CodeHighlightBlockTests {
    private func contents(_ text: String) -> [(String, CodeHighlight.Language)] {
        CodeHighlight.blocks(in: text).map { (String(text[$0.range]), $0.language) }
    }

    @Test func fencedBlockWithLanguageTag() {
        let got = contents("notes\n```swift\nlet x = 1\n```\nafter")
        #expect(got.count == 1)
        #expect(got.first?.0 == "let x = 1")
        #expect(got.first?.1 == .swift)
    }

    @Test func fenceAliasesAndUnknownTags() {
        #expect(CodeHighlight.Language(fenceTag: "py") == .python)
        #expect(CodeHighlight.Language(fenceTag: "JS") == .javascript)
        #expect(CodeHighlight.Language(fenceTag: "bash") == .shell)
        #expect(CodeHighlight.Language(fenceTag: "rust") == .generic)
        #expect(CodeHighlight.Language(fenceTag: "") == .generic)
    }

    @Test func multipleBlocksAndProseBetween() {
        let text = "```python\nx = 1\n```\nprose\n```\ny = 2\n```"
        let got = contents(text)
        #expect(got.map(\.0) == ["x = 1", "y = 2"])
        #expect(got.map(\.1) == [.python, .generic])
    }

    @Test func unclosedFenceRunsToEnd() {
        let got = contents("```swift\nlet x = 1\nlet y = 2")
        #expect(got.map(\.0) == ["let x = 1\nlet y = 2"])
    }

    @Test func plainNoteWithoutFencesHasNoBlocks() {
        #expect(CodeHighlight.blocks(for: ContextNote(text: "just words\nlet x = 1")).isEmpty)
        #expect(CodeHighlight.tokens(for: ContextNote(text: "just words")).isEmpty)
    }

    @Test func codeModeBodyIsSingleInferredBlock() {
        let note = ContextNote(text: "code\nfunc add() -> Int { 1 }")
        let blocks = CodeHighlight.blocks(for: note)
        #expect(blocks.count == 1)
        #expect(blocks.first.map { String(note.text[$0.range]) } == "func add() -> Int { 1 }")
        #expect(blocks.first?.language == .swift)
    }

    @Test func codeModeFencesWinOverWholeBody() {
        let note = ContextNote(text: "code\n```python\ndef f():\n    pass\n```")
        let blocks = CodeHighlight.blocks(for: note)
        #expect(blocks.count == 1)
        #expect(blocks.first?.language == .python)
        #expect(blocks.first.map { String(note.text[$0.range]) } == "def f():\n    pass")
    }

    @Test func detection() {
        #expect(CodeHighlight.detect("#!/bin/bash\necho hi") == .shell)
        #expect(CodeHighlight.detect("#!/usr/bin/env python3\nprint(1)") == .python)
        #expect(CodeHighlight.detect("def main():\n    print(None)") == .python)
        #expect(CodeHighlight.detect("const f = () => console.log(1)") == .javascript)
        #expect(CodeHighlight.detect("import Foundation\nfunc f() {}") == .swift)
        #expect(CodeHighlight.detect("hello world, no code here") == .generic)
    }
}

@Suite struct CodeHighlightTokenizerTests {
    private func spans(_ text: String, _ language: CodeHighlight.Language) -> [(CodeHighlight.TokenKind, String)] {
        CodeHighlight.tokens(in: text, language: language).filter { ![.identifier, .type, .function].contains($0.kind) }.map { ($0.kind, String(text[$0.range])) }
    }

    @Test func swiftKeywordStringCommentNumber() {
        let got = spans("let name = \"bo\" // greet\nreturn 42", .swift)
        #expect(got.map(\.1) == ["let", "\"bo\"", "// greet", "return", "42"])
        #expect(got.map(\.0) == [.keyword, .string, .comment, .keyword, .number])
    }

    @Test func keywordsNeedWholeWord() {
        let got = spans("letter lets let1 let", .swift)
        #expect(got.map(\.1) == ["let"])
    }

    @Test func stringAndCommentContentsStayUntokenized() {
        let got = spans("let s = \"return 42\" // func 7", .swift)
        #expect(got.map(\.1) == ["let", "\"return 42\"", "// func 7"])
        #expect(got.map(\.0) == [.keyword, .string, .comment])
    }

    @Test func escapedQuoteStaysInString() {
        let got = spans("let s = \"a \\\" b\" + 1", .swift)
        #expect(got.map(\.1) == ["let", "\"a \\\" b\"", "1"])
    }

    @Test func unterminatedStringStopsAtLineEnd() {
        let got = spans("let s = \"oops\nlet t = 2", .swift)
        #expect(got.map(\.1) == ["let", "\"oops", "let", "2"])
    }

    @Test func blockCommentSpansLines() {
        let got = spans("1 /* let\nx */ 2", .swift)
        #expect(got.map(\.1) == ["1", "/* let\nx */", "2"])
        #expect(got.map(\.0) == [.number, .comment, .number])
    }

    @Test func pythonHashCommentAndTripleString() {
        let got = spans("def f(): # make\n    s = \"\"\"return 1\"\"\"\n    return True", .python)
        #expect(got.map(\.1) == ["def", "# make", "\"\"\"return 1\"\"\"", "return", "True"])
        #expect(got.map(\.0) == [.keyword, .comment, .string, .keyword, .keyword])
    }

    @Test func shellHashMidWordIsNotComment() {
        let got = spans("echo a#b # real", .shell)
        #expect(got.map(\.1) == ["echo", "# real"])
    }

    @Test func jsTemplateStringSpansLines() {
        let got = spans("const s = `a\nb`", .javascript)
        #expect(got.map(\.1) == ["const", "`a\nb`"])
        #expect(got.map(\.0) == [.keyword, .string])
    }

    @Test func numberFormats() {
        let got = spans("0xFF 0b101 1_000 3.14 1e-3 1.toString sha256", .javascript)
        #expect(got.filter { $0.0 == .number }.map(\.1) == ["0xFF", "0b101", "1_000", "3.14", "1e-3", "1"])
    }

    @Test func noteLevelTokensCoverFencedBlockOnly() {
        let note = ContextNote(text: "let outside = 1\n```swift\nlet inside = 2\n```")
        let got = CodeHighlight.tokens(for: note).map { String(note.text[$0.range]) }
        #expect(got == ["let", "inside", "2"])
    }

    @Test func codeModeNoteTokensSkipTriggerLine() {
        let note = ContextNote(text: "code\nlet x = \"hi\"")
        let got = CodeHighlight.tokens(for: note).map { ($0.kind, String(note.text[$0.range])) }
        #expect(got.map(\.1) == ["let", "x", "\"hi\""])
        #expect(got.map(\.0) == [.keyword, .identifier, .string])
    }

    @Test func emptyAndWhitespaceTokenizeToNothing() {
        #expect(spans("", .swift).isEmpty)
        #expect(spans("  \n \t ", .generic).isEmpty)
    }
}
