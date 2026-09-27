import AppKit
import ContextDomain
import Foundation

/// One-click handoff: txt, Markdown, PDF, clipboard. No accounts involved.
public enum NoteExport: Sendable {
    public static func plainText(_ note: ContextNote) -> String { note.text }

    public static func markdown(_ note: ContextNote) -> String { note.text }

    @MainActor
    public static func pdf(_ note: ContextNote) throws -> Data {
        let text = note.text.isEmpty ? " " : note.text
        let attr = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
        )
        // Direct PDF data from the attributed string.
        let range = NSRange(location: 0, length: attr.length)
        if let data = try? attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.plain]) {
            _ = data
        }
        // Reliable path: draw text pages into an NSPDFImageRep-backed context.
        let pageSize = NSSize(width: 612, height: 792)
        let margins: CGFloat = 48
        let textRect = NSRect(x: margins, y: margins, width: pageSize.width - margins * 2, height: pageSize.height - margins * 2)
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: [CGRect(origin: .zero, size: pageSize)], nil)
        else { throw ExportError.renderFailed }
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        ctx.beginPDFPage(nil)
        attr.draw(in: textRect)
        ctx.endPDFPage()
        ctx.closePDF()
        NSGraphicsContext.restoreGraphicsState()
        guard pdfData.length > 0 else { throw ExportError.renderFailed }
        return pdfData as Data
    }

    public static func writeFile(_ note: ContextNote, kind: ExportKind, to url: URL) throws {
        switch kind {
        case .txt, .markdown:
            try plainText(note).write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            let data = try MainActor.assumeIsolated { try pdf(note) }
            try data.write(to: url)
        }
    }

    public static func copyToClipboard(_ note: ContextNote) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
    }

    // MARK: - One-click handoff

    /// Sends the note to Apple Notes via osascript. Throws when Notes is
    /// missing or the script fails so the UI can show a graceful alert.
    @MainActor
    public static func sendToAppleNotes(_ note: ContextNote) throws {
        let (title, body) = Handoff.titleAndBody(for: note)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", Handoff.appleNotesScript(title: title, body: body)]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw ExportError.handoffFailed("Apple Notes did not accept the note.") }
    }

    /// Writes the note as Markdown into the Obsidian vault folder.
    @MainActor
    public static func sendToObsidian(_ note: ContextNote, vault: URL) throws {
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let dest = Handoff.obsidianFileURL(for: note, vault: vault)
        // Avoid clobbering an existing vault note with the same title.
        var final = dest
        var n = 2
        while FileManager.default.fileExists(atPath: final.path) {
            final = vault.appendingPathComponent("\(dest.deletingPathExtension().lastPathComponent)-\(n).md")
            n += 1
        }
        try markdown(note).write(to: final, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([final])
    }

    /// Opens Bear's x-callback-url to create the note.
    @MainActor
    public static func sendToBear(_ note: ContextNote) throws {
        guard let url = Handoff.bearURL(for: note) else { throw ExportError.handoffFailed("Could not build the Bear URL.") }
        if !NSWorkspace.shared.open(url) {
            throw ExportError.handoffFailed("Bear is not installed or did not open.")
        }
    }

    public enum ExportKind: Sendable { case txt, markdown, pdf }
    public enum ExportError: Error {
        case renderFailed
        case handoffFailed(String)
    }
}
