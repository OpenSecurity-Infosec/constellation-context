import AppKit

@main
@MainActor
final class ContextAppDelegate: NSObject, NSApplicationDelegate {
    private var main: ContextWindowController?
    private var status: ContextStatusItem?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ContextAppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        let controller = ContextWindowController()
        main = controller
        let status = ContextStatusItem()
        self.status = status
        status.install(toggle: {}, newNote: {})
        ContextHotKeys.install { [weak controller] in controller?.toggle() }
        controller.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func toggleWindow(_ sender: Any?) { main?.toggle() }
    @objc func newNote(_ sender: Any?) { main?.newNote() }
    @objc func nextNote(_ sender: Any?) { main?.nextNote() }
    @objc func prevNote(_ sender: Any?) { main?.prevNote() }
    @objc func showSettings(_ sender: Any?) { main?.openSettings() }
    @objc func showVoid(_ sender: Any?) { main?.openVoid() }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Context", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New Note", action: #selector(newNote(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "Next Note", action: #selector(nextNote(_:)), keyEquivalent: "]")
        file.addItem(withTitle: "Previous Note", action: #selector(prevNote(_:)), keyEquivalent: "[")
        file.addItem(.separator())
        file.addItem(withTitle: "The Void", action: #selector(showVoid(_:)), keyEquivalent: "")
        let fileItem = NSMenuItem(); fileItem.submenu = file; menu.addItem(fileItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Toggle Context", action: #selector(toggleWindow(_:)), keyEquivalent: "a")
        let windowItem = NSMenuItem(); windowItem.submenu = window; menu.addItem(windowItem)
        return menu
    }
}
