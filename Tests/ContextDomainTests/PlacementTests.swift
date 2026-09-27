import ContextDomain
import Foundation
import Testing

@Suite struct PlacementTests {
    @Test func dockDefaultsOn() throws {
        // showInDock defaults true; decode tolerates older settings files.
        let settings = try JSONDecoder().decode(
            ContextSettings.self, from: "{}".data(using: .utf8)!
        )
        #expect(settings.showInDock)
        #expect(settings.showMenuBarExtra)
    }

    @Test func dockRoundTrips() throws {
        var settings = try JSONDecoder().decode(
            ContextSettings.self, from: "{}".data(using: .utf8)!
        )
        settings.showInDock = false
        settings.showMenuBarExtra = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ContextSettings.self, from: data)
        #expect(!decoded.showInDock)
        #expect(!decoded.showMenuBarExtra)
    }
}
