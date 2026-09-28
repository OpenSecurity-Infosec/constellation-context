import ContextDomain
import ContextStore
import Foundation
import Testing

@Suite struct StageFlushTests {
    private func store(file: String) -> (NoteStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: url)
        return (NoteStore(fileURL: url), url)
    }

    @Test func stagedTextReadsImmediately() {
        let (s, _) = store(file: "ctx-stage-\(UUID().uuidString).json")
        let n = s.create(text: "hello")
        s.stage(id: n.id, text: "typed")
        #expect(s.note(id: n.id)?.text == "typed")
    }

    @Test func stageSkipsDiskUntilFlush() throws {
        let (s, url) = store(file: "ctx-stage-\(UUID().uuidString).json")
        let n = s.create(text: "hello")
        let before = try Data(contentsOf: url)
        s.stage(id: n.id, text: "typed but unsaved")
        // Disk still holds the pre-stage snapshot.
        #expect(try Data(contentsOf: url) == before)
        s.flush()
        let after = try JSONDecoder().decode([ContextNote].self, from: Data(contentsOf: url))
        #expect(after.first { $0.id == n.id }?.text == "typed but unsaved")
    }

    @Test func updateStillSavesImmediately() throws {
        let (s, url) = store(file: "ctx-stage-\(UUID().uuidString).json")
        let n = s.create(text: "hello")
        s.update(id: n.id, text: "saved now")
        let after = try JSONDecoder().decode([ContextNote].self, from: Data(contentsOf: url))
        #expect(after.first { $0.id == n.id }?.text == "saved now")
    }

    @Test func flushIsSafeRedundant() throws {
        let (s, url) = store(file: "ctx-stage-\(UUID().uuidString).json")
        s.create(text: "hello")
        s.flush()
        s.flush()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
