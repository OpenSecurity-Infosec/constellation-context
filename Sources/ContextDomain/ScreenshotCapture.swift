import Foundation

/// Screenshot-to-text flow: runs the system interactive region picker
/// (`screencapture -i`) into a tempfile, then feeds the file to the
/// existing on-device OCR path. Domain holds the testable seams
/// (arguments, tempfile naming, image validation); AppKit owns Process.
public enum ScreenshotCapture: Sendable {
    /// Arguments for interactive region capture into `outputPath`.
    /// `-i` picker, `-t png` lossless for OCR, `-x` no shutter sound.
    public static func arguments(outputPath: String) -> [String] {
        ["-i", "-x", "-t", "png", outputPath]
    }

    /// Fresh tempfile under the caches dir, unique per capture.
    public static func tempFileURL() -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ConstellationContext", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("capture-\(UUID().uuidString).png")
    }

    /// True when the capture file is a readable non-empty image file.
    public static func isUsableCapture(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > 0
        else { return false }
        return url.pathExtension.lowercased() == "png"
    }

    /// Removes the tempfile after OCR. Best-effort.
    public static func cleanup(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
