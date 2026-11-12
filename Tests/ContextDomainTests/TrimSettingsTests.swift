import Foundation
import Testing
@testable import ContextDomain

@Test func legacyAppearanceAndExtensionSettingsAreInert() throws {
    let data = Data(#"{"themeMode":"dark","colorTheme":"forest","translucentWindow":true,"extensionsAllowNetwork":true,"fontSize":18}"#.utf8)
    let settings = try JSONDecoder().decode(ContextSettings.self, from: data)
    #expect(settings.themeMode == .system)
    #expect(settings.colorTheme == .paper)
    #expect(!settings.translucentWindow)
    #expect(!settings.extensionsAllowNetwork)
    #expect(settings.fontSize == 18)
}
