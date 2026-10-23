import Carbon
import MeetyCore

/// Atalhos globais do ditado pelo Carbon (não pedem permissão de Acessibilidade).
final class DictationHotkeys {
    enum Action: UInt32 {
        case dictate = 1  // o atalho escolhido nas Configurações
        case escape       // Esc, só durante a gravação
    }

    /// (ação, apertou): apertou = false quando a tecla é solta.
    var handler: ((Action, Bool) -> Void)?

    private var refs: [Action: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // Outros atalhos do app (se algum dia houver) têm outra assinatura.
            guard id.signature == DictationHotkeys.signature else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<DictationHotkeys>.fromOpaque(userData).takeUnretainedValue()
            if let action = Action(rawValue: id.id) {
                me.handler?(action, GetEventKind(event) == UInt32(kEventHotKeyPressed))
            }
            return noErr
        }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private static let signature = OSType(0x4D45_4459)  // 'MEDY'

    /// Registra o atalho do ditado. Devolve false se outro app já usa a mesma combinação.
    @discardableResult
    func register(_ shortcut: DictationShortcut) -> Bool {
        unregister(.dictate)
        let (key, mods): (Int, Int) = switch shortcut {
        case .optionSpace: (kVK_Space, optionKey)
        case .controlOptionSpace: (kVK_Space, controlKey | optionKey)
        case .commandShiftSpace: (kVK_Space, cmdKey | shiftKey)
        case .optionCommandD: (kVK_ANSI_D, optionKey | cmdKey)
        }
        return register(.dictate, key: key, mods: mods)
    }

    func registerEscape() { register(.escape, key: kVK_Escape, mods: 0) }

    @discardableResult
    private func register(_ action: Action, key: Int, mods: Int) -> Bool {
        guard refs[action] == nil else { return true }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        guard RegisterEventHotKey(UInt32(key), UInt32(mods), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref else { return false }
        refs[action] = ref
        return true
    }

    func unregister(_ action: Action) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }
}
