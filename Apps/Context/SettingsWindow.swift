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

    var body: some View {
        Form {
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
                }
            Toggle("Show menu bar icon", isOn: $showMenuBar)
                .onChange(of: showMenuBar) {
                    ContextSettings.shared.showMenuBarExtra = showMenuBar
                    ContextSettings.shared.save()
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
            Text("Toggle with ⌥A from anywhere. Notes stay on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
