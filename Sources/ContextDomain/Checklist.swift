import Foundation

/// Checklist line model for `list` notes and `- [ ]` markers.
public struct ChecklistItem: Equatable, Sendable, Identifiable {
    public var id: Int
    public var checked: Bool
    public var text: String
    public var indent: Int
    public var marker: Marker

    public enum Marker: Equatable, Sendable {
        case checkbox
        case bullet
        case numbered(Int)

        /// Cycles checkbox → bullet → numbered → checkbox, per Antinote ⌘⇧M.
        public func next() -> Marker {
            switch self {
            case .checkbox: return .bullet
            case .bullet: return .numbered(1)
            case .numbered: return .checkbox
            }
        }
    }

    public static func parse(_ noteText: String) -> [ChecklistItem] {
        let lines = noteText.components(separatedBy: .newlines)
        // Skip trigger line when present.
        let body = lines.first?.trimmingCharacters(in: .whitespaces).lowercased() == "list" ? Array(lines.dropFirst()) : lines
        var items: [ChecklistItem] = []
        var number = 1
        for (i, line) in body.enumerated() {
            let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[ ] ") || trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
                let checked = trimmed.lowercased().hasPrefix("[x] ")
                items.append(ChecklistItem(id: i, checked: checked, text: String(trimmed.dropFirst(4)), indent: leading / 2, marker: .checkbox))
                number = 1
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                items.append(ChecklistItem(id: i, checked: false, text: String(trimmed.dropFirst(2)), indent: leading / 2, marker: .bullet))
                number = 1
            } else if let match = trimmed.range(of: #"^(\d+)[.)]\s+"#, options: .regularExpression) {
                let digits = trimmed[match].filter(\.isNumber)
                number = Int(digits) ?? number
                items.append(ChecklistItem(id: i, checked: false, text: String(trimmed[match.upperBound...]), indent: leading / 2, marker: .numbered(number)))
                number += 1
            } else if !trimmed.isEmpty {
                items.append(ChecklistItem(id: i, checked: false, text: trimmed, indent: leading / 2, marker: .checkbox))
                number = 1
            } else {
                number = 1
            }
        }
        return items
    }

    public static func serialize(_ items: [ChecklistItem], trigger: Bool) -> String {
        var number = 1
        var lines = items.map { item -> String in
            let pad = String(repeating: "  ", count: item.indent)
            switch item.marker {
            case .checkbox:
                number = 1
                return "\(pad)\(item.checked ? "[x]" : "[ ]") \(item.text)"
            case .bullet:
                number = 1
                return "\(pad)- \(item.text)"
            case .numbered:
                defer { number += 1 }
                return "\(pad)\(number). \(item.text)"
            }
        }
        if trigger { lines.insert("list", at: 0) }
        return lines.joined(separator: "\n")
    }

    /// Drag-reorders one checklist line: moves the body line at `from` to
    /// post-removal insertion index `to` (both body-relative, as produced by
    /// parse). The `list` trigger line never moves. Tick, indent, and
    /// markers ride along because lines move verbatim.
    public static func move(text: String, from: Int, to: Int) -> String {
        var lines = text.components(separatedBy: .newlines)
        let offset = lines.first?.trimmingCharacters(in: .whitespaces).lowercased() == "list" ? 1 : 0
        let src = from + offset, dst = to + offset
        guard lines.indices.contains(src), src != dst else { return text }
        let line = lines.remove(at: src)
        let clamped = max(offset, min(dst, lines.count))
        lines.insert(line, at: clamped)
        return lines.joined(separator: "\n")
    }

    /// Block move: moving a parent carries its contiguous nested block
    /// (deeper-indented item lines) with it, so the subtree stays intact
    /// with indent preserved. `from` is the body id of the block head;
    /// `to` is the body id of the line that should FOLLOW the block after
    /// the move, or `bodyLineCount` to append at the end. Landing inside
    /// the block (or exactly home) is a no-op.
    public static func moveBlock(text: String, from: Int, to anchor: Int, bodyLineCount: Int) -> String {
        var lines = text.components(separatedBy: .newlines)
        let offset = lines.first?.trimmingCharacters(in: .whitespaces).lowercased() == "list" ? 1 : 0
        let src = from + offset
        guard lines.indices.contains(src) else { return text }
        var end = src
        let baseIndent = indentOf(lines[src])
        var i = src + 1
        while i < lines.count, isItemLine(lines[i]), indentOf(lines[i]) > baseIndent {
            end = i
            i += 1
        }
        let endBody = end - offset
        if anchor >= from, anchor <= endBody + 1 { return text }
        let block = Array(lines[src...end])
        lines.removeSubrange(src...end)
        let insertAt: Int
        if anchor >= bodyLineCount {
            insertAt = lines.count
        } else if anchor > endBody {
            insertAt = anchor - block.count + offset
        } else {
            insertAt = anchor + offset
        }
        lines.insert(contentsOf: block, at: max(offset, min(insertAt, lines.count)))
        return lines.joined(separator: "\n")
    }

    /// Display-order move for SwiftUI .onMove: `ids` are body ids in parse
    /// order, `to` is SwiftUI's post-removal insertion position. Returns the
    /// (fromId, anchorId) pair for moveBlock, where the anchor is the body
    /// id of the row that should follow the block (or bodyLineCount to
    /// append at the end).
    public static func moveDisplay(ids: [Int], from: IndexSet, to displayTo: Int, bodyLineCount: Int) -> (from: Int, anchor: Int) {
        guard let raw = from.first, ids.indices.contains(raw) else { return (0, 0) }
        let srcId = ids[raw]
        var remaining = ids
        remaining.remove(at: raw)
        guard displayTo < remaining.count else { return (srcId, bodyLineCount) }
        return (srcId, remaining[max(0, displayTo)])
    }

    private static func indentOf(_ line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
    }

    private static func isItemLine(_ line: String) -> Bool {
        !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public static func toggle(text: String, id: Int) -> String {
        var lines = text.components(separatedBy: .newlines)
        let offset = lines.first?.trimmingCharacters(in: .whitespaces).lowercased() == "list" ? 1 : 0
        let idx = id + offset
        guard lines.indices.contains(idx) else { return text }
        var line = lines[idx]
        if line.contains("[ ]") {
            line = line.replacingOccurrences(of: "[ ]", with: "[x]")
        } else if line.contains("[x]") || line.contains("[X]") {
            line = line.replacingOccurrences(of: "[X]", with: "[ ]").replacingOccurrences(of: "[x]", with: "[ ]")
        } else {
            line = "[x] \(line.trimmingCharacters(in: .whitespaces))"
        }
        lines[idx] = line
        return lines.joined(separator: "\n")
    }

    /// Tab nests the target line one level deeper; Shift+Tab outdents (floor 0).
    public static func indent(text: String, id: Int, direction: IndentDirection) -> String {
        var lines = text.components(separatedBy: .newlines)
        let offset = lines.first?.trimmingCharacters(in: .whitespaces).lowercased() == "list" ? 1 : 0
        let idx = id + offset
        guard lines.indices.contains(idx) else { return text }
        var line = lines[idx]
        switch direction {
        case .in:
            line = "  " + line
        case .out:
            if line.hasPrefix("  ") { line = String(line.dropFirst(2)) }
            else if line.hasPrefix("\t") { line = String(line.dropFirst()) }
            else if line.hasPrefix(" ") { line = String(line.dropFirst()) }
        }
        lines[idx] = line
        return lines.joined(separator: "\n")
    }

    public enum IndentDirection { case `in`, out }

    /// ⌘⇧M cycles the current line: checkbox ↔ bullet ↔ numbered.
    /// Markers live in the text itself.
    public static func cycleMarker(text: String, id: Int) -> String {
        var lines = text.components(separatedBy: .newlines)
        let offset = lines.first?.trimmingCharacters(in: .whitespaces).lowercased() == "list" ? 1 : 0
        let idx = id + offset
        guard lines.indices.contains(idx) else { return text }
        let line = lines[idx]
        let leading = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[ ] ") || trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
            let rest = String(trimmed.dropFirst(4))
            lines[idx] = "\(leading)- \(rest)"
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
            let rest = String(trimmed.dropFirst(2))
            lines[idx] = "\(leading)1. \(rest)"
        } else if trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil,
                  let match = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            let rest = String(trimmed[match.upperBound...])
            lines[idx] = "\(leading)[ ] \(rest)"
        } else if !trimmed.isEmpty {
            lines[idx] = "\(leading)[ ] \(trimmed)"
        }
        return lines.joined(separator: "\n")
    }
}
