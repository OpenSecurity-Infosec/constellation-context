import Foundation
import Testing
@testable import ContextDomain

@Suite struct PaperTypeTests {
    @Test func oldSettingsDefaultToPlainPaper() throws {
        let settings = try JSONDecoder().decode(ContextSettings.self, from: Data("{}".utf8))
        #expect(settings.paperType == .plain)
    }

    @Test func paperChoiceSurvivesSettingsRoundTrip() throws {
        for paper in PaperType.allCases {
            let settings = ContextSettings(paperType: paper)
            let restored = try JSONDecoder().decode(ContextSettings.self, from: JSONEncoder().encode(settings))
            #expect(restored.paperType == paper)
            #expect(restored.lightColorTheme == settings.lightColorTheme)
            #expect(restored.darkColorTheme == settings.darkColorTheme)
        }
    }
}
