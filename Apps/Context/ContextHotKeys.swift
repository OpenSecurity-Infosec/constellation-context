import Carbon
import Foundation

/// Global hotkey. Default ⌥A like Antinote.
enum ContextHotKeys {
    nonisolated(unsafe) private static var refs: [EventHotKeyRef] = []
    nonisolated(unsafe) private static var handler: EventHandlerRef?
    nonisolated(unsafe) private static var action: (@MainActor () -> Void)?
    private static let signature = OSType(0x43545821) // CTX!

    static func install(_ onFire: @escaping @MainActor () -> Void) {
        action = onFire
        uninstall()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in ContextHotKeys.handle() },
            1, &spec, nil, &handler
        )
        guard status == noErr else { return }
        var hotRef: EventHotKeyRef?
        let hotID = EventHotKeyID(signature: signature, id: 1)
        let code = ContextSettings.shared.hotKeyCode
        let mods = ContextSettings.shared.hotKeyModifiers
        if RegisterEventHotKey(code, mods, hotID, GetApplicationEventTarget(), 0, &hotRef) == noErr, let hotRef {
            refs.append(hotRef)
        }
    }

    private static func handle() -> OSStatus {
        Task { @MainActor in action?() }
        return noErr
    }

    static func uninstall() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }
}
