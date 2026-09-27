import ContextDomain
import Foundation
import Testing

@Suite struct ThemeModeTests {
    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(ThemeMode.dark)
        #expect(try JSONDecoder().decode(ThemeMode.self, from: data) == .dark)
    }

    @Test func resolvesAppearance() {
        #expect(ThemeMode.system.isDark(systemDark: true))
        #expect(!ThemeMode.system.isDark(systemDark: false))
        #expect(ThemeMode.light.isDark(systemDark: true) == false)
        #expect(ThemeMode.dark.isDark(systemDark: false))
        #expect(ThemeMode.allCases.count == 3)
    }
}
