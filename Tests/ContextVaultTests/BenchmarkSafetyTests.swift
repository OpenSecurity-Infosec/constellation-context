import Foundation
import Testing
@testable import ContextVault

struct BenchmarkSafetyTests {
    @Test func listingDoesNotFollowExternalSymlink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try "private".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("external.md"), withDestinationURL: outside)
        try "[[link]] ![[embed]]".write(to: root.appendingPathComponent("local.md"), atomically: true, encoding: .utf8)
        let connector = ObsidianConnector(id: "test", displayName: "Test", root: root)
        #expect(try await connector.list().count == 1)
        #expect(try await connector.search("private").isEmpty)
        #expect(try await connector.search("[[link]]").count == 1)
    }
}
