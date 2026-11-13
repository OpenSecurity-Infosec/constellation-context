import ContextDomain
import ContextVault
import SwiftUI

/// Settings: text size, float-on-top, menu bar extra.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private let window: NSWindow

    private init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 820),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Context Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @State private var fontSize: Double = Double(ContextSettings.shared.fontSize)
    @State private var pinOnTop: Bool = ContextSettings.shared.pinOnTop
    @State private var showMenuBar: Bool = ContextSettings.shared.showMenuBarExtra
    @State private var showInDock: Bool = ContextSettings.shared.showInDock

    var body: some View {
        Form {
            Section("Placement") {
                Toggle("Show in Dock", isOn: $showInDock)
                    .accessibilityIdentifier("settings.showInDock")
                    .onChange(of: showInDock) {
                        ContextSettings.shared.showInDock = showInDock
                        ContextSettings.shared.save()
                        PlacementRelayer.dockChanged()
                    }
                Toggle("Show menu bar icon", isOn: $showMenuBar)
                    .accessibilityIdentifier("settings.showMenuBar")
                    .onChange(of: showMenuBar) {
                        ContextSettings.shared.showMenuBarExtra = showMenuBar
                        ContextSettings.shared.save()
                        PlacementRelayer.menuBarChanged()
                    }
                Toggle("Pin above other windows", isOn: $pinOnTop)
                    .accessibilityIdentifier("settings.pinOnTop")
                    .onChange(of: pinOnTop) {
                        ContextSettings.shared.pinOnTop = pinOnTop
                        ContextSettings.shared.save()
                        PinRelayer.pinOnTop = pinOnTop
                    }
            }
            Section("Appearance") {
                Slider(value: $fontSize, in: 11...22, step: 1) {
                    Text("Text size: \(Int(fontSize))")
                }
                .accessibilityIdentifier("settings.textSize")
                .onChange(of: fontSize) {
                    ContextSettings.shared.fontSize = CGFloat(fontSize)
                    ContextSettings.shared.save()
                    ThemeRelayer.lookChanged()
                }
            }
            Section("Vaults") {
                BaseVaultSettingsRow()
                LinkedVaultsSection()
            }
            Section("Clipboard") {
                ClipboardSettingsRow()
            }
            Section("AI") {
                AISettingsRow()
            }
            Text("Toggle with ⌥A from anywhere. Notes are Markdown files in your base vault, on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

/// Relays Settings placement changes to the live app without a restart.
/// Wired by the app delegate at launch; no-ops in tests.
@MainActor
enum PlacementRelayer {
    nonisolated(unsafe) static var dockChanged: () -> Void = {}
    nonisolated(unsafe) static var menuBarChanged: () -> Void = {}
}

/// Relays pin changes to the live overlay window. No restart needed.
@MainActor
enum PinRelayer {
    nonisolated(unsafe) static var pinOnTop: Bool = false {
        didSet { onChange?(pinOnTop) }
    }
    nonisolated(unsafe) static var onChange: ((Bool) -> Void)?
}

/// Relays color-theme / translucency changes to the live overlay.
@MainActor
enum ThemeRelayer {
    nonisolated(unsafe) static var lookChanged: () -> Void = {}
}

/// Base vault location (ADR-0002). Context's own notes live here as
/// Markdown; the folder opens in Obsidian as-is.
private struct BaseVaultSettingsRow: View {
    @State private var path: String = (ContextSettings.shared.baseVaultPath.map { URL(fileURLWithPath: $0) }
        ?? BaseVault.defaultRoot).path

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Base vault")
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .accessibilityIdentifier("settings.baseVault.reveal")
                Button("Change…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    panel.message = "Choose a folder for Context's notes"
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    path = url.path
                    VaultRelayer.baseVaultChanged(url)
                }
                .accessibilityIdentifier("settings.baseVault.change")
            }
            Text(path)
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}

/// Clipboard history on/off. Concealed copies (passwords) are never kept.
private struct ClipboardSettingsRow: View {
    @State private var enabled: Bool = ContextSettings.shared.clipboardHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Keep clipboard history", isOn: $enabled)
                .onChange(of: enabled) {
                    ContextSettings.shared.clipboardHistory = enabled
                    ContextSettings.shared.save()
                    ClipboardRelayer.changed()
                }
                .accessibilityIdentifier("settings.clipboardHistory")
            Text("Copies become editable notes in the Clipboard pad. Password-manager copies are skipped; untouched entries leave after 30 days.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor
enum ClipboardRelayer {
    nonisolated(unsafe) static var changed: () -> Void = {}
}

/// Relays a base-vault change to the live store.
@MainActor
enum VaultRelayer {
    nonisolated(unsafe) static var baseVaultChanged: (URL) -> Void = { _ in }
}
