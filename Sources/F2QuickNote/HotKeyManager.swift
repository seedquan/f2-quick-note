import AppKit
import Carbon.HIToolbox

/// Registers global hotkeys via Carbon. Unlike CGEvent taps, registration
/// itself needs no Accessibility permission.
final class HotKeyManager {
    struct RegistrationResult {
        let f2: Bool
        let commandF2: Bool
    }

    private enum HotKey: UInt32 {
        case f2 = 1
        case commandF2 = 2
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private let f2Callback: () -> Void
    private let commandF2Callback: () -> Void

    init(f2Callback: @escaping () -> Void,
         commandF2Callback: @escaping () -> Void) {
        self.f2Callback = f2Callback
        self.commandF2Callback = commandF2Callback
    }

    /// Registers F2 and Command-F2. Both require "Use F1, F2, etc. as
    /// standard function keys" unless the user also holds Fn.
    @discardableResult
    func registerHotKeys() -> RegistrationResult {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                DispatchQueue.main.async { manager.handle(hotKeyID.id) }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandlerRef
        )
        guard installStatus == noErr else {
            return RegistrationResult(f2: false, commandF2: false)
        }

        return RegistrationResult(
            f2: register(.f2, modifiers: 0),
            commandF2: register(.commandF2, modifiers: UInt32(cmdKey))
        )
    }

    private func register(_ hotKey: HotKey, modifiers: UInt32) -> Bool {
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x46_32_51_4E), // 'F2QN'
            id: hotKey.rawValue
        )
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_F2),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
            return true
        }
        return false
    }

    private func handle(_ id: UInt32) {
        switch HotKey(rawValue: id) {
        case .f2:
            f2Callback()
        case .commandF2:
            commandF2Callback()
        case nil:
            break
        }
    }

    func unregister() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRefs.removeAll()
        eventHandlerRef = nil
    }

    deinit { unregister() }
}
