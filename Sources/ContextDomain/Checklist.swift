import Foundation

/// Checklist line model for `list` notes and `- [ ]` markers.
public struct ChecklistItem: Equatable, Sendable, Identifiable {
    public var id: Int
    public var checked: Bool
    public var text: String
    public var indent: Int

    public static func parse(_ noteText: String) -> [ChecklistItem] {
        let lines = noteText.components(separatedBy: .newlines)
        // Skip trigger line when present.
        let body = lines.first?.trimmingCharacters(in: .whitespaces).lowercased() == "list" ? Array(lines.dropFirst()) : lines
        var items: [ChecklistItem] = []
        for (i, line) in body.enumerated() {
            let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[ ] ") || trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
                let checked = trimmed.lowercased().hasPrefix("[x] ")
                items.append(ChecklistItem(id: i, checked: checked, text: String(trimmed.dropFirst(4)), indent: leading / 2))
            } else if !trimmed.isEmpty {
                items.append(ChecklistItem(id: i, checked: false, text: trimmed, indent: leading / 2))
            }
        }
        return items
    }

    public static func serialize(_ items: [ChecklistItem], trigger: Bool) -> String {
        var lines = items.map { item -> String in
            let pad = String(repeating: "  ", count: item.indent)
            return "\(pad)\(item.checked ? "[x]" : "[ ]") \(item.text)"
        }
        if trigger { lines.insert("list", at: 0) }
        return lines.joined(separator: "\n")
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
}
