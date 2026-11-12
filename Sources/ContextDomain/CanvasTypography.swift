import Foundation

/// How the canvas sets type. Display only: the file on disk stays plain
/// Markdown, and nothing here changes the text.
public enum CanvasTypography {
    /// Title size relative to the body size.
    public static let titleScale: CGFloat = 1.85
    /// Extra space between lines of one paragraph, relative to body size.
    public static let lineSpacing: CGFloat = 0.3
    /// Extra space after each line (each line is a paragraph), relative to
    /// body size.
    public static let paragraphSpacing: CGFloat = 0.45
    /// Space between the title and the body, relative to body size.
    public static let titleSpacing: CGFloat = 0.9

    /// All notes use Markdown typography; legacy trigger words are ordinary text.
    public static func isProse(_ text: String) -> Bool { true }

    /// The range of a prose note's first line, including its line break, so
    /// it can be set as the title. Nil for a blank first line.
    public static func titleRange(in text: String) -> NSRange? {
        guard isProse(text) else { return nil }
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let line = ns.lineRange(for: NSRange(location: 0, length: 0))
        let content = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : line
    }

}
