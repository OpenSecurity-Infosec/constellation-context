import ContextDomain
import Foundation
import Testing

@Suite struct ColorThemeTests {
    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(ColorTheme.forest)
        #expect(try JSONDecoder().decode(ColorTheme.self, from: data) == .forest)
    }

    @Test func threeNamedThemes() {
        #expect(ColorTheme.allCases.count == 3)
        #expect(ColorTheme.mocha.displayName == "Mocha")
    }

    @Test func palettesAreHex() {
        for theme in ColorTheme.allCases {
            for hex in [theme.palette.light, theme.palette.dark, theme.palette.accent] {
                #expect(hex.count == 6)
                #expect(UInt32(hex, radix: 16) != nil)
            }
        }
    }

    @Test func settingsRoundTrips() throws {
        var settings = try JSONDecoder().decode(
            ContextSettings.self, from: "{}".data(using: .utf8)!
        )
        settings.colorTheme = .paper
        settings.translucentWindow = true
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ContextSettings.self, from: data)
        #expect(decoded.colorTheme == .paper)
        #expect(decoded.translucentWindow)
    }

    @Test func settingsDefaults() throws {
        let settings = try JSONDecoder().decode(
            ContextSettings.self, from: "{}".data(using: .utf8)!
        )
        #expect(settings.colorTheme == .mocha)
        #expect(!settings.translucentWindow)
    }

    @Test func appearanceChoicesRoundTripAndResolve() throws {
        var settings = ContextSettings(lightColorTheme: .paper, darkColorTheme: .forest)
        settings = try JSONDecoder().decode(ContextSettings.self, from: JSONEncoder().encode(settings))
        #expect(settings.colorTheme(systemDark: false) == .paper)
        #expect(settings.colorTheme(systemDark: true) == .forest)
        settings.themeMode = .light
        #expect(settings.colorTheme(systemDark: true) == .paper)
        settings.themeMode = .dark
        #expect(settings.colorTheme(systemDark: false) == .forest)
    }

    @Test func legacyThemeMigratesToBothAppearances() throws {
        for theme in ColorTheme.allCases {
            let data = Data("{\"colorTheme\":\"\(theme.rawValue)\"}".utf8)
            let settings = try JSONDecoder().decode(ContextSettings.self, from: data)
            #expect(settings.lightColorTheme == theme)
            #expect(settings.darkColorTheme == theme)
        }
        let defaults = try JSONDecoder().decode(ContextSettings.self, from: Data("{}".utf8))
        #expect(defaults.lightColorTheme == .mocha)
        #expect(defaults.darkColorTheme == .mocha)
    }
}
