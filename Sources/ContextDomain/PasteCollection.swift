import Foundation

/// AutoPaste collection for `paste` notes: every clipboard/paste entry the
/// monitor delivers becomes its own item in the note text, separated from
/// its neighbours by a bare `---` delimiter line. Items are read back by
/// splitting on that line, so the plain text stays the source of truth —
/// hand edits that respect the delimiter round-trip for free.
///
/// Collected entries pass through `PlainText.sanitizePasteboard` on the way
/// in, which already drops bare `---` lines (markdown table junk), so a
/// collected item can never forge a delimiter and split itself.
public enum PasteCollection {
    /// Line that separates two collected items, alone on its own line.
    public static let delimiter = "---"

    /// Default separator between items in the copy-all payload.
    public static let joinedSeparator = "\n\n"

    /// Parses the collected items out of a note's text. The `paste`
    /// trigger line is not an item. A body with no delimiter (notes
    /// collected before delimiters existed, or hand-typed text) reads as
    /// a single item — its original paste boundaries are unknowable.
    public static func items(in noteText: String) -> [String] {
        let note = ContextNote(text: noteText)
        let body = note.kind == .paste ? note.bodyWithoutTrigger : noteText
        var items: [String] = []
        var chunk: [String] = []
        func flush() {
            let text = chunk.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(text)
            }
            chunk = []
        }
        for line in body.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces) == delimiter {
                flush()
            } else {
                chunk.append(line)
            }
        }
        flush()
        return items
    }

    /// Serializes items back to note text, optionally under the trigger.
    public static func serialize(items: [String], trigger: Bool) -> String {
        let body = items.joined(separator: "\n\(delimiter)\n")
        guard trigger else { return body }
        return body.isEmpty ? "paste" : "paste\n\n\(body)"
    }

    /// Appends one raw clipboard/paste entry as a new item. The entry is
    /// sanitized like any paste. No-ops (returns `noteText` verbatim)
    /// when the entry sanitizes to nothing, repeats the last item
    /// back-to-back (double-fire / same clip recopied), or is exactly
    /// the copy-all payload of the current items — copy-all writes that
    /// payload to the pasteboard and it must not re-collect itself.
    public static func appending(_ rawEntry: String, to noteText: String) -> String {
        let clean = PlainText.sanitizePasteboard(rawEntry)
        guard !clean.isEmpty else { return noteText }
        let existing = items(in: noteText)
        guard clean != existing.last else { return noteText }
        guard existing.isEmpty || clean != existing.joined(separator: joinedSeparator)
        else { return noteText }
        let trigger = ContextNote(text: noteText).kind == .paste
        return serialize(items: existing + [clean], trigger: trigger)
    }

    /// The copy-all payload: every item joined, no trigger, no delimiters.
    public static func joined(_ noteText: String, separator: String = joinedSeparator) -> String {
        items(in: noteText).joined(separator: separator)
    }

    /// Empties the collection, keeping the note in `paste` mode.
    public static func cleared(_ noteText: String) -> String {
        serialize(items: [], trigger: ContextNote(text: noteText).kind == .paste)
    }

    /// Drops the most recently collected item. No-op when empty.
    public static func removingLastItem(from noteText: String) -> String {
        let existing = items(in: noteText)
        guard !existing.isEmpty else { return noteText }
        let trigger = ContextNote(text: noteText).kind == .paste
        return serialize(items: Array(existing.dropLast()), trigger: trigger)
    }

    /// Mode-bar line: armed state plus a live item count so the user can
    /// see collection happening and learn the copy-all chord.
    public static func statusLine(itemCount: Int, armed: Bool) -> String {
        guard armed else { return "Type paste + Return to collect copies." }
        switch itemCount {
        case 0: return "Collecting — everything you copy lands here as its own item."
        case 1: return "1 paste collected · ⌘⇧C copies it"
        default: return "\(itemCount) pastes collected · ⌘⇧C copies all joined"
        }
    }
}
