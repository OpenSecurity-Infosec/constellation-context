import AppKit
import ContextDomain
import ContextExport
import ContextHarness
import ContextStore

/// Every note action, built once. The same items appear in the menu bar's
/// Note menu, the canvas's right-click menu, and the header's ⋯ button, so
/// the canvas itself needs no visible controls.
extension ContextWindowController {
    enum NoteMenuPlace {
        /// The menu bar. It may carry key equivalents.
        case menuBar
        /// Right-click on the canvas.
        case canvas
        /// The header's ⋯ button. Also reaches the app's other windows.
        case more
    }

    func noteMenuItems(for place: NoteMenuPlace) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        items.append(ActionMenuItem.submenu("AI", aiActions.map { action in
            ActionMenuItem(action.title) { [weak self] in self?.runAI(action) }
        }))
        if let info = cachedProjectInfo {
            items.append(ActionMenuItem.submenu("Project", projectMenuItems(info)))
        } else {
            let projects = pads.filter(\.isProject)
            if !projects.isEmpty {
                items.append(ActionMenuItem.submenu("Send to Project", projects.map { p in
                    ActionMenuItem(p.title) { [weak self] in self?.sendToProject(p.title) }
                }))
            }
        }
        items.append(ActionMenuItem.submenu("Export", exportMenuItems()))
        items.append(.separator())
        items.append(ActionMenuItem("Move to Trash", identifier: "note.trash") { [weak self] in self?.trashCurrent() })
        if place == .more {
            items.append(.separator())
            items.append(ActionMenuItem("Search…") { [weak self] in self?.openSearch() })
            items.append(ActionMenuItem("The Void") { [weak self] in self?.openVoid() })
            items.append(ActionMenuItem("Library") { [weak self] in self?.openLibrary() })
            items.append(ActionMenuItem("Settings…") { [weak self] in self?.openSettings() })
        }
        return items
    }

    /// Pops the full note menu under the header's ⋯ button.
    func showMoreMenu() {
        guard let view = window.contentView else { return }
        let menu = NSMenu()
        noteMenuItems(for: .more).forEach(menu.addItem)
        let y = view.isFlipped ? ZenMetrics.headerHeight : view.bounds.height - ZenMetrics.headerHeight
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.width - 44, y: y), in: view)
    }

    private func projectMenuItems(_ info: ProjectInfo) -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            ActionMenuItem("Copy as Context", key: "c", modifiers: [.command, .shift]) { [weak self] in
                self?.copyProjectContext()
            },
            ActionMenuItem("Copy Import Line") { [weak self] in self?.copyImportLine() },
            ActionMenuItem("Reveal Context File") { [weak self] in self?.revealProjectFile() },
            .separator(),
            ActionMenuItem("Add Document…") { [weak self] in self?.addProjectDocument() },
        ]
        if !info.documents.isEmpty || !info.references.isEmpty {
            let documents = info.documents.map { name in
                ActionMenuItem(name) { [weak self] in self?.removeProjectDocument(name) }
            }
            let references = info.references.map { r in
                ActionMenuItem("\(r.title) (linked)") { [weak self] in self?.detachProjectReference(r.ref) }
            }
            items.append(ActionMenuItem.submenu("Remove", documents + references))
        }
        items.append(.separator())
        var targets = HarnessKind.allCases.map { kind in
            ActionMenuItem("\(kind.displayName) (not built yet)", isOn: info.harnesses.contains(kind)) { [weak self] in
                self?.toggleHarness(kind)
            }
        }
        targets.append(ActionMenuItem("Constellation Router (not built yet)", isOn: info.routerSync) { [weak self] in
            self?.toggleRouterSync()
        })
        items.append(ActionMenuItem.submenu("Deliver To", targets))
        items.append(ActionMenuItem("Deliver Now") { [weak self] in self?.deliverNow() })
        return items
    }

    private func exportMenuItems() -> [NSMenuItem] {
        [
            ActionMenuItem("Copy") { [weak self] in self?.copyNote() },
            ActionMenuItem("Quick Export .txt") { [weak self] in self?.quickExport(kind: .txt) },
            ActionMenuItem("Quick Export Markdown") { [weak self] in self?.quickExport(kind: .markdown) },
            ActionMenuItem("Quick Export PDF") { [weak self] in self?.quickExport(kind: .pdf) },
            .separator(),
            ActionMenuItem("Save .txt As…") { [weak self] in self?.export(kind: .txt) },
            ActionMenuItem("Save Markdown As…") { [weak self] in self?.export(kind: .markdown) },
            ActionMenuItem("Save PDF As…") { [weak self] in self?.export(kind: .pdf) },
            .separator(),
            ActionMenuItem("Send to Apple Notes") { [weak self] in self?.sendToAppleNotes() },
            ActionMenuItem("Send to Obsidian") { [weak self] in self?.sendToObsidian() },
            ActionMenuItem("Send to Bear") { [weak self] in self?.sendToBear() },
        ]
    }
}
