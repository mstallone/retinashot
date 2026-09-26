import Carbon.HIToolbox

/// System-wide hot keys through Carbon. Works from a background app and needs no Accessibility permission.
@MainActor
final class HotKeys {
    typealias Handler = @MainActor (_ pressed: Bool) -> Void
    private static let signature = OSType(0x5253_4854) // 'RSHT'
    private var handlers: [UInt32: Handler] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    init() {
        var kinds = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated { // Carbon delivers hot-key events on the main thread
                Unmanaged<HotKeys>.fromOpaque(context!).takeUnretainedValue().handlers[id.id]?(pressed)
            }
            return noErr
        }, kinds.count, &kinds, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @discardableResult
    func register(_ key: Int, modifiers: Int = 0, handler: @escaping Handler) -> UInt32 {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(modifiers), EventHotKeyID(signature: Self.signature, id: id),
                            GetApplicationEventTarget(), 0, &ref)
        handlers[id] = handler
        refs[id] = ref
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }
}
