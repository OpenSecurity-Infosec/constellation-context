import ContextDomain
import SwiftUI

/// Settings: text size, float-on-top, menu bar extra.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private let window: NSWindow

    private init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.titled, .closable],
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
            Slider(value: $fontSize, in: 11...22, step: 1) {
                Text("Text size: \(Int(fontSize))")
            }.onChange(of: fontSize) {
                ContextSettings.shared.fontSize = CGFloat(fontSize)
                ContextSettings.shared.save()
            }
            Toggle("Pin above other windows", isOn: $pinOnTop)
                .onChange(of: pinOnTop) {
                    ContextSettings.shared.pinOnTop = pinOnTop
                    ContextSettings.shared.save()
                    PinRelayer.pinOnTop = pinOnTop
                }
            Toggle("Show menu bar icon", isOn: $showMenuBar)
                .onChange(of: showMenuBar) {
                    ContextSettings.shared.showMenuBarExtra = showMenuBar
                    ContextSettings.shared.save()
                    PlacementRelayer.menuBarChanged()
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
            SyncSettingsRow()
            ExtensionSettingsRow()
            Text("Toggle with ⌥A from anywhere. Notes stay on this Mac unless iCloud sync is on.")
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

/// iCloud sync toggle + status. Uses the user's own iCloud; off by default.
private struct SyncSettingsRow: View {
    @State private var enabled: Bool = ContextSettings.shared.iCloudSyncEnabled
    @State private var status: String = SyncManager.shared.statusText()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Sync notes with iCloud", isOn: $enabled)
                .onChange(of: enabled) {
                    SyncManager.shared.isEnabled = enabled
                    status = SyncManager.shared.statusText()
                }
            Text(status)
                .font(.caption).foregroundStyle(.secondary)
            if enabled {
                Button("Sync now") {
                    SyncManager.shared.sync()
                    status = SyncManager.shared.statusText()
                }
                .font(.caption)
            }
        }
        .onAppear {
            enabled = ContextSettings.shared.iCloudSyncEnabled
            status = SyncManager.shared.statusText()
        }
    }
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
