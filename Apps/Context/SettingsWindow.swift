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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
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
    @State private var vaultPath: String = ContextSettings.shared.obsidianVaultPath ?? ""
    @State private var theme: ThemeMode = ContextSettings.shared.themeMode
    @State private var showInDock: Bool = ContextSettings.shared.showInDock
    @State private var colorTheme: ColorTheme = ContextSettings.shared.colorTheme
    @State private var translucent: Bool = ContextSettings.shared.translucentWindow

    var body: some View {
        Form {
            Section("Placement") {
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) {
                        ContextSettings.shared.showInDock = showInDock
                        ContextSettings.shared.save()
                        PlacementRelayer.dockChanged()
                    }
                Toggle("Show menu bar icon", isOn: $showMenuBar)
                    .onChange(of: showMenuBar) {
                        ContextSettings.shared.showMenuBarExtra = showMenuBar
                        ContextSettings.shared.save()
                        PlacementRelayer.menuBarChanged()
                    }
                Toggle("Pin above other windows", isOn: $pinOnTop)
                    .onChange(of: pinOnTop) {
                        ContextSettings.shared.pinOnTop = pinOnTop
                        ContextSettings.shared.save()
                        PinRelayer.pinOnTop = pinOnTop
                    }
            }
            Picker("Appearance", selection: $theme) {
                Text("System").tag(ThemeMode.system)
                Text("Light").tag(ThemeMode.light)
                Text("Dark").tag(ThemeMode.dark)
            }
            .pickerStyle(.segmented)
            .onChange(of: theme) {
                ContextSettings.shared.themeMode = theme
                ContextSettings.shared.save()
                ContextTheme.apply(mode: theme)
            }
            Picker("Color theme", selection: $colorTheme) {
                ForEach(ColorTheme.allCases, id: \.self) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: colorTheme) {
                ContextSettings.shared.colorTheme = colorTheme
                ContextSettings.shared.save()
                ThemeRelayer.lookChanged()
            }
            Toggle("Translucent window", isOn: $translucent)
                .onChange(of: translucent) {
                    ContextSettings.shared.translucentWindow = translucent
                    ContextSettings.shared.save()
                    ThemeRelayer.lookChanged()
                }
            Slider(value: $fontSize, in: 11...22, step: 1) {
                Text("Text size: \(Int(fontSize))")
            }.onChange(of: fontSize) {
                ContextSettings.shared.fontSize = CGFloat(fontSize)
                ContextSettings.shared.save()
                ThemeRelayer.lookChanged()
            }
            HStack {
                TextField("Obsidian vault folder", text: $vaultPath)
                    .onChange(of: vaultPath) {
                        let trimmed = vaultPath.trimmingCharacters(in: .whitespaces)
                        ContextSettings.shared.obsidianVaultPath = trimmed.isEmpty ? nil : trimmed
                        ContextSettings.shared.save()
                    }
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        vaultPath = url.path
                        ContextSettings.shared.obsidianVaultPath = url.path
                        ContextSettings.shared.save()
                    }
                }
            }
            BaseVaultSettingsRow()
            LinkedVaultsSection()
            ExtensionSettingsRow()
            Text("Toggle with ⌥A from anywhere. Notes are Markdown files in your base vault, on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
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

/// Relays a base-vault change to the live store.
@MainActor
enum VaultRelayer {
    nonisolated(unsafe) static var baseVaultChanged: (URL) -> Void = { _ in }
}

/// JS extension privacy + folder. Scripts run sandboxed with no network
/// bridge; the toggle stays OFF unless the user opts in.
private struct ExtensionSettingsRow: View {
    @State private var allowNetwork: Bool = ContextSettings.shared.extensionsAllowNetwork

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Let extensions call their own APIs", isOn: $allowNetwork)
                .onChange(of: allowNetwork) {
                    ContextSettings.shared.extensionsAllowNetwork = allowNetwork
                    ContextSettings.shared.save()
                }
            HStack {
                Text("Extensions folder")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([JSExtension.defaultFolder()])
                }
                .font(.caption)
            }
            Text("Drop .js files with `// name: x` headers to add ::commands.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            allowNetwork = ContextSettings.shared.extensionsAllowNetwork
        }
    }
}
