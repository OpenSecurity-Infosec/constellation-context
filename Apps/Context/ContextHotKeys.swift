import Carbon
import ContextDomain
import Foundation

/// Global hotkeys. Default ⌥A toggles the overlay like Antinote,
/// ⌥⇧S captures a screen region to text via on-device OCR.
enum ContextHotKeys {
    nonisolated(unsafe) private static var refs: [EventHotKeyRef] = []
    nonisolated(unsafe) private static var handler: EventHandlerRef?
    nonisolated(unsafe) private static var action: (@MainActor () -> Void)?
    nonisolated(unsafe) private static var captureAction: (@MainActor () -> Void)?
    private static let signature = OSType(0x43545821) // CTX!

    static func install(_ onFire: @escaping @MainActor () -> Void) {
        action = onFire
        uninstall()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in ContextHotKeys.handle(event: event) },
            1, &spec, nil, &handler
        )
        guard status == noErr else { return }
        register(code: ContextSettings.shared.hotKeyCode, mods: ContextSettings.shared.hotKeyModifiers, id: 1)
        register(code: 1, mods: 0x0A00, id: 2) // ANSI S + option + shift
    }

    static func onCapture(_ onFire: @escaping @MainActor () -> Void) {
        captureAction = onFire
    }

    private static func register(code: UInt32, mods: UInt32, id: UInt32) {
        var hotRef: EventHotKeyRef?
        let hotID = EventHotKeyID(signature: signature, id: id)
        if RegisterEventHotKey(code, mods, hotID, GetApplicationEventTarget(), 0, &hotRef) == noErr, let hotRef {
            refs.append(hotRef)
        }
    }

    private static func handle(event: EventRef?) -> OSStatus {
        var hotID = EventHotKeyID()
        if event != nil,
           GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                             nil, MemoryLayout<EventHotKeyID>.size, nil, &hotID) == noErr,
           hotID.id == 2
        {
            Task { @MainActor in captureAction?() }
        } else {
            Task { @MainActor in action?() }
        }
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
