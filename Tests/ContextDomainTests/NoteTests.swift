import ContextDomain
import Foundation
import Testing

@Suite struct NoteTests {
    @Test func triggerDetection() {
        #expect(ContextNote(text: "math\n1+1").kind == .math)
        #expect(ContextNote(text: "LIST\n- a").kind == .list)
        #expect(ContextNote(text: "hello").kind == .plain)
        #expect(ContextNote(text: "count\n1 2 3").kind == .count)
    }

    @Test func bodyStripsTrigger() {
        #expect(ContextNote(text: "math\n2+2").bodyWithoutTrigger == "2+2")
    }

    @Test func sanitizeStripsBullets() {
        #expect(PlainText.sanitize("- hello") == "hello")
        #expect(PlainText.sanitize("1. hello") == "hello")
        #expect(PlainText.sanitize("  • hello  ") == "  hello")
    }

    @Test func sanitizeKeepsRelativeIndent() {
        let pasted = "- top\n    - nested\n        - deep\n1) numbered"
        #expect(PlainText.sanitize(pasted) == "top\n    nested\n        deep\nnumbered")
    }

    @Test func sanitizeUnwrapsTables() {
        let pasted = "| name | qty |\n| --- | --- |\n| milk | 2 |"
        #expect(PlainText.sanitize(pasted) == "name  qty\nmilk  2")
    }

    @Test func sanitizeStripsQuotesAndEntities() {
        #expect(PlainText.sanitize("> quoted\n>> deep") == "quoted\ndeep")
        #expect(PlainText.sanitize("fish &amp; chips &#39;yum&#39;") == "fish & chips 'yum'")
        #expect(PlainText.sanitize("a &#x27;b&#x27; c") == "a 'b' c")
    }

    @Test func sanitizeNormalizesSmartPunctuation() {
        #expect(PlainText.sanitize("\u{201C}hi\u{201D} \u{2019}yo\u{2019} \u{2026}") == "\"hi\" 'yo' ...")
    }

    @Test func sanitizeCollapsesBlankRuns() {
        #expect(PlainText.sanitize("\n\na\n\n\n\nb\n\n") == "a\n\nb")
    }

    @Test func sanitizeHandlesCRLFAndTabs() {
        #expect(PlainText.sanitize("a\r\n\t- b") == "a\n  b")
    }

    @Test func statsIgnoreComments() {
        let s = NoteStats.compute(for: "one two\n// skip me\nthree")
        #expect(s.words == 3)
        #expect(s.lines == 2)
    }

    @Test func breakdownRows() {
        let rows = NoteStats.breakdown(for: "one two\n// skip\n\nthree")
        #expect(rows.count == 4)
        #expect(rows[0] == NoteStats.LineRow(words: 2, characters: 7, ignored: false))
        #expect(rows[1].ignored && rows[2].ignored)
        #expect(rows[3] == NoteStats.LineRow(words: 1, characters: 5, ignored: false))
    }

    @Test func breakdownDisplay() {
        #expect(NoteStats.LineRow(words: 3, characters: 18, ignored: false).display == "3w · 18c")
        #expect(NoteStats.LineRow(words: 0, characters: 0, ignored: true).display == "—")
    }

    @Test func totalsAgreeWithBreakdown() {
        let text = "one two\n// skip me\n\nthree four five"
        let rows = NoteStats.breakdown(for: text)
        let active = rows.filter { !$0.ignored }
        let s = NoteStats.compute(for: text)
        #expect(s.lines == active.count)
        #expect(s.words == active.map(\.words).reduce(0, +))
        #expect(s.characters == active.map(\.characters).reduce(0, +) + max(0, active.count - 1))
    }

    @Test func checklistToggle() {
        let toggled = ChecklistItem.toggle(text: "list\n[ ] milk", id: 0)
        #expect(toggled.contains("[x] milk"))
    }
}

@Suite struct TimerDisplayTests {
    @Test func nameSkipsDurationSpecs() {
        #expect(NoteTimer.name(from: "timer\n25m\nDeep work") == "Deep work")
        #expect(NoteTimer.name(from: "timer\npomodoro") == "")
        #expect(NoteTimer.name(from: "timer\n10:00\nStandup") == "Standup")
        #expect(NoteTimer.name(from: "timer") == "")
    }

    @Test func nameUsesFirstDescriptiveLine() {
        #expect(NoteTimer.name(from: "timer\nBread") == "Bread")
        #expect(NoteTimer.name(from: "timer\n\n  Laundry  \n25m") == "Laundry")
    }

    @Test func fractionTracksCountdown() {
        let t = NoteTimer()
        t.start(mode: .countdown(seconds: 100))
        #expect(t.totalDuration == 100)
        let f = t.fractionDone ?? -1
        #expect(f >= 0 && f <= 0.05)
        t.stop()
    }

    @Test func stopwatchHasNoFraction() {
        let t = NoteTimer()
        t.start(mode: .stopwatch)
        #expect(t.totalDuration == nil)
        #expect(t.fractionDone == nil)
        t.stop()
    }

    @Test func formatHandlesHours() {
        #expect(NoteTimer.format(90) == "1:30")
        #expect(NoteTimer.format(3661) == "1:01:01")
        #expect(NoteTimer.format(0) == "0:00")
    }
}

@Suite struct TimerSceneTests {
    @Test func runningCountdownLine() {
        #expect(TimerScene.statusLine(elapsed: 450, remaining: 750, running: true) == "7:30 in · 12:30 left")
    }

    @Test func pausedCountdownLine() {
        #expect(TimerScene.statusLine(elapsed: 60, remaining: 540, running: false) == "Paused · 9:00 left")
    }

    @Test func stopwatchLine() {
        #expect(TimerScene.statusLine(elapsed: 5, remaining: nil, running: true) == "0:05 up")
        #expect(TimerScene.statusLine(elapsed: 0, remaining: nil, running: false) == "")
    }

    @Test func finishedHasNoStatusLine() {
        #expect(TimerScene.statusLine(elapsed: 1200, remaining: 0, running: false) == "")
    }

    @Test func finishLine() {
        #expect(TimerScene.finishLine(total: 1200) == "Done in 20:00")
        #expect(TimerScene.finishLine(total: nil) == "Done")
    }

    @Test func ringLabel() {
        #expect(TimerScene.ringLabel(fraction: 0.362) == "36%")
        #expect(TimerScene.ringLabel(fraction: 0) == "0%")
        #expect(TimerScene.ringLabel(fraction: 1.5) == "100%")
    }
}

@Suite struct VoidExpiryTests {    @Test func liveNotesHaveNoCountdown() {
        #expect(NoteExpiry.daysLeft(for: ContextNote(text: "hi")) == nil)
        #expect(NoteExpiry.label(for: ContextNote(text: "hi")) == nil)
    }

    @Test func freshTrashShowsThirtyDays() {
        let now = Date()
        var n = ContextNote(text: "gone")
        n.trashedAt = now
        #expect(NoteExpiry.daysLeft(for: n, now: now) == 30)
        #expect(NoteExpiry.label(for: n, now: now) == "30 days left")
    }

    @Test func oldTrashCountsDown() {
        let now = Date()
        var n = ContextNote(text: "gone")
        n.trashedAt = now.addingTimeInterval(-29 * 24 * 3600)
        #expect(NoteExpiry.daysLeft(for: n, now: now) == 1)
        #expect(NoteExpiry.label(for: n, now: now) == "1 day left")
    }

    @Test func overdueTrashClampsAtZero() {
        let now = Date()
        var n = ContextNote(text: "gone")
        n.trashedAt = now.addingTimeInterval(-40 * 24 * 3600)
        #expect(NoteExpiry.daysLeft(for: n, now: now) == 0)
        #expect(NoteExpiry.label(for: n, now: now) == "expires soon")
    }
}

@Suite struct ScreenshotCaptureTests {
    @Test func argumentsPickRegionToFile() {
        let args = ScreenshotCapture.arguments(outputPath: "/tmp/x.png")
        #expect(args.contains("-i"))
        #expect(args.contains("-x"))
        #expect(args.last == "/tmp/x.png")
    }

    @Test func tempFilesAreUniquePng() {
        let a = ScreenshotCapture.tempFileURL()
        let b = ScreenshotCapture.tempFileURL()
        #expect(a != b)
        #expect(a.pathExtension == "png")
    }

    @Test func missingFileIsNotUsable() {
        #expect(!ScreenshotCapture.isUsableCapture(at: URL(fileURLWithPath: "/tmp/context-nope-\(UUID().uuidString).png")))
    }

    @Test func nonEmptyPngIsUsable() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        #expect(ScreenshotCapture.isUsableCapture(at: url))
        ScreenshotCapture.cleanup(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func emptyFileIsNotUsable() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ctx-\(UUID().uuidString).png")
        try Data().write(to: url)
        #expect(!ScreenshotCapture.isUsableCapture(at: url))
        try? FileManager.default.removeItem(at: url)
    }
}
