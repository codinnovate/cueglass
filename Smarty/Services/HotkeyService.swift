import AppKit
import Carbon
import Foundation

enum HotkeyAction: UInt32, CaseIterable, Sendable {
    case toggleOverlay = 1
    case togglePause = 2
}

/// Nonisolated relay so Carbon callbacks never touch a @MainActor object off-queue.
private final class HotkeyRelay: @unchecked Sendable {
    static let shared = HotkeyRelay()
    private let lock = NSLock()
    private var handlers: [UInt32: () -> Void] = [:]

    func setHandler(id: UInt32, handler: @escaping () -> Void) {
        lock.lock()
        handlers[id] = handler
        lock.unlock()
    }

    func clear() {
        lock.lock()
        handlers.removeAll()
        lock.unlock()
    }

    func invoke(id: UInt32) {
        lock.lock()
        let handler = handlers[id]
        lock.unlock()
        guard let handler else { return }
        // Carbon can deliver off-main; hop via MainActor before touching UI/session.
        Task { @MainActor in
            handler()
        }
    }

    /// Nonisolated C callback — must not be created inside a @MainActor method (SE-0420).
    static let eventHandler: EventHandlerUPP = { (_, event, _) -> OSStatus in
        guard let event else { return noErr }
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        HotkeyRelay.shared.invoke(id: hotKeyID.id)
        return noErr
    }
}

@MainActor
final class HotkeyService {
    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    func registerDefaults(
        onToggleOverlay: @escaping () -> Void,
        onTogglePause: @escaping () -> Void
    ) {
        HotkeyRelay.shared.setHandler(id: HotkeyAction.toggleOverlay.rawValue, handler: onToggleOverlay)
        HotkeyRelay.shared.setHandler(id: HotkeyAction.togglePause.rawValue, handler: onTogglePause)

        installHandlerIfNeeded()

        register(
            action: .toggleOverlay,
            keyCode: UInt32(kVK_ANSI_H),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        register(
            action: .togglePause,
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | shiftKey)
        )
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        HotkeyRelay.shared.clear()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private func register(action: HotkeyAction, keyCode: UInt32, modifiers: UInt32) {
        if let existing = hotKeyRefs[action] {
            UnregisterEventHotKey(existing)
            hotKeyRefs[action] = nil
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x534D5259), id: action.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            AppLog.overlay.error("Failed to register hotkey \(action.rawValue)")
            return
        }
        hotKeyRefs[action] = hotKeyRef
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Handler must be nonisolated — Carbon may deliver off-main (SE-0420).
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            HotkeyRelay.eventHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        if status != noErr {
            AppLog.overlay.error("Failed to install hotkey handler")
        }
    }
}
