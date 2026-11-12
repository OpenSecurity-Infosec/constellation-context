import Foundation

/// A note body split for the canvas: runs of text, and image embeds that
/// stand on their own line (`![alt](path)` or Obsidian's `![[file]]`).
public enum MarkdownBlock: Equatable, Sendable {
    case text(String)
    case image(target: String, alt: String)
}

public enum MarkdownBlocks {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"]

    public static func parse(_ body: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var run: [String] = []
        var inFence = false
        func flush() {
            if !run.isEmpty { blocks.append(.text(run.joined(separator: "\n"))) }
            run = []
        }
        for line in body.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle() }
            if !inFence, let image = embed(in: line) {
                flush()
                blocks.append(image)
            } else {
                run.append(line)
            }
        }
        flush()
        return blocks
    }

    /// The image a whole line embeds, if it is only an image embed.
    static func embed(in line: String) -> MarkdownBlock? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("![["), t.hasSuffix("]]") {
            let inner = String(t.dropFirst(3).dropLast(2))
            let target = inner.split(separator: "|", maxSplits: 1).first.map(String.init) ?? inner
            guard isImage(target) else { return nil }
            return .image(target: target, alt: target)
        }
        if t.hasPrefix("!["), t.hasSuffix(")"), let mid = t.range(of: "](") {
            let alt = String(t[t.index(t.startIndex, offsetBy: 2)..<mid.lowerBound])
            var target = String(t[mid.upperBound..<t.index(before: t.endIndex)])
            if let space = target.firstIndex(of: " ") { target = String(target[..<space]) }
            target = target.removingPercentEncoding ?? target
            guard !target.isEmpty else { return nil }
            return .image(target: target, alt: alt)
        }
        return nil
    }

    static func isImage(_ target: String) -> Bool {
        imageExtensions.contains((target as NSString).pathExtension.lowercased())
    }

    /// Finds an embedded file the way Obsidian does: relative to the note,
    /// then relative to the vault root, then by file name anywhere in the
    /// vault (outside hidden folders). Remote URLs are returned as-is.
    public static func resolve(_ target: String, noteFolder: URL, vaultRoot: URL) -> URL? {
        if let url = URL(string: target), let scheme = url.scheme, ["http", "https"].contains(scheme) { return url }
        let fm = FileManager.default
        let rootPath = vaultRoot.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        for base in [noteFolder, vaultRoot] {
            let candidate = base.appendingPathComponent(target).standardizedFileURL
            guard candidate.path.hasPrefix(rootPrefix) else { continue }
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        let name = (target as NSString).lastPathComponent
        let walker = fm.enumerator(at: vaultRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = walker?.nextObject() as? URL {
            if url.lastPathComponent == name { return url }
        }
        return nil
    }
}
