import AppKit
import ContextDomain

@main
@MainActor
final class ContextAppDelegate: NSObject, NSApplicationDelegate {
    private var main: ContextWindowController?
    private var status: ContextStatusItem?
    private var pendingURL: URL?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ContextAppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// Dock / menu-bar placement. Dock on by default; menu-bar-only uses
    /// accessory policy so Context lives in the menu bar like Antinote.
    func applyPlacement() {
        if ContextSettings.shared.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        status?.refresh(
            toggle: { [weak self] in self?.main?.toggle() },
            newNote: { [weak self] in self?.main?.newNote() }
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        let controller = ContextWindowController()
        main = controller
        let status = ContextStatusItem()
        self.status = status
        status.install(
            toggle: { [weak controller] in controller?.toggle() },
            newNote: { [weak controller] in controller?.newNote() }
        )
        PlacementRelayer.dockChanged = { [weak self] in self?.applyPlacement() }
        PlacementRelayer.menuBarChanged = { [weak self] in self?.applyPlacement() }
        PinRelayer.onChange = { [weak controller] _ in controller?.updatePin() }
        ThemeRelayer.lookChanged = { [weak controller] in controller?.applyLook() }
        applyPlacement()
        ContextHotKeys.install { [weak controller] in controller?.toggle() }
        controller.show()
        SyncManager.shared.start()
        if let pending = pendingURL {
            pendingURL = nil
            handleSchemeURL(pending)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Handles `context://` URLs from Raycast/Alfred/scripts/Shortcuts.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if URLScheme.parse(url) != nil {
                handleSchemeURL(url)
            }
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReply:)),
            forEventClass: UInt32(kInternetEventClass),
            andEventID: UInt32(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReply _: NSAppleEventDescriptor) {
        if let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
           let url = URL(string: s), URLScheme.parse(url) != nil
        {
            if main == nil {
                pendingURL = url
            } else {
                handleSchemeURL(url)
            }
        }
    }

    private func handleSchemeURL(_ url: URL) {
        guard let intent = URLScheme.parse(url) else { return }
        switch intent {
        case .open:
            main?.show()
        case .newNote(let text):
            main?.newNoteWithText(text)
        case .search(let query):
            main?.openSearch(query: query)
        case .append(let text):
            main?.appendToCurrent(text)
        }
    }

    @objc func toggleWindow(_ sender: Any?) { main?.toggle() }
    @objc func newNote(_ sender: Any?) { main?.newNote() }
    @objc func nextNote(_ sender: Any?) { main?.nextNote() }
    @objc func prevNote(_ sender: Any?) { main?.prevNote() }
    @objc func cycleMarker(_ sender: Any?) { main?.cycleMarkerAtCaret() }
    @objc func sendToAppleNotes(_ sender: Any?) { main?.sendToAppleNotes() }
    @objc func sendToObsidian(_ sender: Any?) { main?.sendToObsidian() }
    @objc func sendToBear(_ sender: Any?) { main?.sendToBear() }
    @objc func openSearch(_ sender: Any?) { main?.openSearch() }
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
        file.addItem(withTitle: "Search Notes…", action: #selector(openSearch(_:)), keyEquivalent: "f")
        let fileItem = NSMenuItem(); fileItem.submenu = file; menu.addItem(fileItem)
        let format = NSMenu(title: "Format")
        let cycle = NSMenuItem(title: "Cycle Line Marker", action: #selector(cycleMarker(_:)), keyEquivalent: "m")
        cycle.keyEquivalentModifierMask = [.command, .shift]
        format.addItem(cycle)
        let formatItem = NSMenuItem(); formatItem.submenu = format; menu.addItem(formatItem)
        let share = NSMenu(title: "Share")
        share.addItem(withTitle: "Send to Apple Notes", action: #selector(sendToAppleNotes(_:)), keyEquivalent: "")
        share.addItem(withTitle: "Send to Obsidian", action: #selector(sendToObsidian(_:)), keyEquivalent: "")
        share.addItem(withTitle: "Send to Bear", action: #selector(sendToBear(_:)), keyEquivalent: "")
        let shareItem = NSMenuItem(); shareItem.submenu = share; menu.addItem(shareItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Toggle Context", action: #selector(toggleWindow(_:)), keyEquivalent: "a")
        let windowItem = NSMenuItem(); windowItem.submenu = window; menu.addItem(windowItem)
        return menu
    }
}
