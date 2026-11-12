import ContextDomain
import Foundation
import Testing

@Suite struct BuildInfoTests {
    private let utc = TimeZone(identifier: "UTC")!

    @Test func labelShowsHashAndLocalBuildTime() {
        let info: [String: Any] = ["CFBundleVersion": "71591b1", "ContextBuildDate": "2026-11-12T10:30:00Z"]
        #expect(BuildInfo.label(from: info, timeZone: utc) == "71591b1 · built 2026-11-12 10:30")
    }

    @Test func labelConvertsToLocalZone() {
        let info: [String: Any] = ["CFBundleVersion": "71591b1", "ContextBuildDate": "2026-11-12T10:30:00Z"]
        let plusOne = TimeZone(secondsFromGMT: 3600)!
        #expect(BuildInfo.label(from: info, timeZone: plusOne) == "71591b1 · built 2026-11-12 11:30")
    }

    @Test func labelFallsBackToHashWithoutBuildDate() {
        #expect(BuildInfo.label(from: ["CFBundleVersion": "abc1234"], timeZone: utc) == "abc1234")
        let bad: [String: Any] = ["CFBundleVersion": "abc1234", "ContextBuildDate": "yesterday"]
        #expect(BuildInfo.label(from: bad, timeZone: utc) == "abc1234")
    }

    @Test func labelDefaultsToDevWhenUnstamped() {
        #expect(BuildInfo.label(from: [:], timeZone: utc) == "dev")
        #expect(BuildInfo.label(from: ["CFBundleVersion": ""], timeZone: utc) == "dev")
    }

    @Test func aboutTextAddsCommitSubjectWhenStamped() {
        let info: [String: Any] = [
            "CFBundleVersion": "71591b1",
            "ContextBuildDate": "2026-11-12T10:30:00Z",
            "ContextCommitSubject": "Saved Search Focus, Partial: preserve query",
        ]
        #expect(BuildInfo.aboutText(from: info, timeZone: utc)
            == "71591b1 · built 2026-11-12 10:30\nSaved Search Focus, Partial: preserve query")
        #expect(BuildInfo.aboutText(from: ["CFBundleVersion": "dev"], timeZone: utc) == "dev")
    }
}
