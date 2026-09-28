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
        #expect(PlainText.sanitize("  • hello  ") == "hello")
    }

    @Test func statsIgnoreComments() {
        let s = NoteStats.compute(for: "one two\n// skip me\nthree")
        #expect(s.words == 3)
        #expect(s.lines == 2)
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

@Suite struct VoidExpiryTests {
    @Test func liveNotesHaveNoCountdown() {
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
