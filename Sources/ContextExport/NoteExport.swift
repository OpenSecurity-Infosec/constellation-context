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

    // MARK: - Quick export

    /// File extension per kind.
    public static func fileExtension(for kind: ExportKind) -> String {
        switch kind {
        case .txt: return "txt"
        case .markdown: return "md"
        case .pdf: return "pdf"
        }
    }

    /// Default export folder: last-used directory, else Downloads.
    public static func defaultFolder(lastUsed: String?) -> URL {
        if let lastUsed, !lastUsed.isEmpty,
           FileManager.default.fileExists(atPath: lastUsed)
        {
            return URL(fileURLWithPath: lastUsed, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    /// Unique destination in `dir` from the note title slug. Never
    /// clobbers: appends -2, -3 when the name exists. `exists` is
    /// injectable so tests never touch disk.
    public static func quickDestination(for note: ContextNote, kind: ExportKind, in dir: URL, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL {
        let (title, _) = Handoff.titleAndBody(for: note)
        let base = Handoff.slug(title)
        let ext = fileExtension(for: kind)
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while exists(candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }

    // MARK: - One-click handoff

    /// Sends the note to Apple Notes via osascript. Throws when Notes is
    /// missing or the script fails so the UI can show a graceful alert.
    @MainActor
    public static func sendToAppleNotes(_ note: ContextNote) throws {
        if Handoff.checkNotes(env: Handoff.Environment.live()) != nil {
            throw ExportError.handoffFailed(Handoff.UnavailableReason.notesMissing.message)
        }
        let (title, body) = Handoff.titleAndBody(for: note)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", Handoff.appleNotesScript(title: title, body: body)]
        do {
            try proc.run()
        } catch {
            throw ExportError.handoffFailed(Handoff.UnavailableReason.notesScriptFailed.message)
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw ExportError.handoffFailed(Handoff.UnavailableReason.notesScriptFailed.message)
        }
    }

    /// Writes the note as Markdown into the Obsidian vault folder.
    /// Refuses bad vault paths instead of creating a fake vault there;
    /// pass createIfMissing only after the user explicitly picks the folder.
    @MainActor
    public static func sendToObsidian(_ note: ContextNote, vault: URL, createIfMissing: Bool = false) throws {
        var env = Handoff.Environment.live()
        if createIfMissing, Handoff.checkVault(path: vault.path, env: env) == .vaultMissing(path: vault.path) {
            try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            env = Handoff.Environment.live()
        }
        if let reason = Handoff.checkVault(path: vault.path, env: env) {
            throw ExportError.handoffFailed(reason.message)
        }
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
    public static func sendToBear(_ note: ContextNote, schemeOpenable: Bool? = nil) throws {
        let openable = schemeOpenable
            ?? (NSWorkspace.shared.urlForApplication(toOpen: URL(string: "bear://")!) != nil)
        if !openable {
            throw ExportError.handoffFailed(Handoff.UnavailableReason.bearMissing.message)
        }
        guard let url = Handoff.bearURL(for: note) else { throw ExportError.handoffFailed("Could not build the Bear URL.") }
        if !NSWorkspace.shared.open(url) {
            throw ExportError.handoffFailed(Handoff.UnavailableReason.bearMissing.message)
        }
    }

    public enum ExportKind: Sendable { case txt, markdown, pdf }
    public enum ExportError: Error {
        case renderFailed
        case handoffFailed(String)

        public var message: String {
            switch self {
            case .renderFailed: return "Context could not render that export."
            case .handoffFailed(let m): return m
            }
        }
    }
}
