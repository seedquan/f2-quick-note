import AppKit
import Carbon.HIToolbox

/// Registers a global hotkey via Carbon. Unlike CGEvent taps this needs no
/// Accessibility permission.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    /// Registers F2 (requires "Use F1, F2, etc. as standard function keys").
    /// Returns false if registration failed (e.g. key taken by another app).
    @discardableResult
    func registerF2() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.callback() }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandlerRef
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x46_32_51_4E), id: 1) // 'F2QN'
        let registerStatus = RegisterEventHotKey(UInt32(kVK_F2), 0, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        return registerStatus == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRef = nil
        eventHandlerRef = nil
    }

    deinit { unregister() }
}
