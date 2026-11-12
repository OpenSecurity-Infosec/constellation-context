import Foundation

/// Naming rules for reactive variables in `math` notes (`name = expr`).
/// One definition shared by the math engine and any UI that validates a
/// name: a name starts with a letter (any script) or `_`, then letters,
/// numbers, or `_`. Names are case-sensitive (`Price` ≠ `price`).
/// Only the conversion keywords `in`/`to` are reserved — trigger words
/// (`sum`, `avg`, …), unit symbols, and currency codes are all usable
/// as variable names; conversion syntax wins on lines shaped like one.
public enum ReactiveVariable {
    public enum NameProblem: Equatable, Sendable {
        case empty
        case invalid
        case reserved
    }

    public static let reservedNames: Set<String> = ["in", "to"]

    public static func isValidName(_ name: String) -> Bool {
        problem(with: name) == nil
    }

    public static func isReservedName(_ name: String) -> Bool {
        reservedNames.contains(name.lowercased())
    }

    /// Nil when `name` (already trimmed) is usable, else why not.
    public static func problem(with name: String) -> NameProblem? {
        guard !name.isEmpty else { return .empty }
        guard let first = name.first, first.isLetter || first == "_" else { return .invalid }
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return .invalid }
        if isReservedName(name) { return .reserved }
        return nil
    }

    /// Identifier tokens in `expression`, in order, deduplicated.
    /// Scans the same alphabet `isValidName` accepts, so a unicode name
    /// is found whole. Numbers never start a token.
    public static func references(in expression: String) -> [String] {
        var refs: [String] = []
        var seen: Set<String> = []
        var current = ""
        func flush() {
            if !current.isEmpty, !seen.contains(current) {
                seen.insert(current)
                refs.append(current)
            }
            current = ""
        }
        for ch in expression {
            if current.isEmpty {
                if ch.isLetter || ch == "_" { current.append(ch) }
            } else if ch.isLetter || ch.isNumber || ch == "_" {
                current.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return refs
    }
}
