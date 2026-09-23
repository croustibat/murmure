import Carbon

// Raccourcis globaux par RegisterEventHotKey (Carbon) : contrairement à un
// moniteur d'événements, ils ne demandent pas l'autorisation « Surveillance
// de l'entrée ». Le système signale l'appui et le relâchement séparément.

struct Raccourci: Equatable {
    var touche: UInt32       // code de touche virtuel (kVK_…)
    var modificateurs: UInt32  // cmdKey, shiftKey, optionKey, controlKey
    var libelle: String      // pour le menu, ex. « ⇧⌘E »

    static let defaut = Raccourci(texte: "cmd+shift+e")!
    static let echap = Raccourci(touche: UInt32(kVK_Escape), modificateurs: 0, libelle: "⎋")

    private static let nommees: [String: Int] = [
        "space": kVK_Space, "espace": kVK_Space, "return": kVK_Return, "tab": kVK_Tab,
        "escape": kVK_Escape, "esc": kVK_Escape, "delete": kVK_Delete,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
        "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10,
        "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15,
        "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
    ]

    // Disposition QWERTY, en dernier recours si la disposition active est illisible.
    private static let ansi: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
        "9": kVK_ANSI_9,
    ]

    init(touche: UInt32, modificateurs: UInt32, libelle: String) {
        self.touche = touche; self.modificateurs = modificateurs; self.libelle = libelle
    }

    // Format « cmd+shift+e » : modificateurs puis une touche, dans n'importe
    // quel ordre. Nil si la combinaison est illisible.
    init?(texte: String) {
        var mods: UInt32 = 0
        var touche: Int?
        var nom = ""
        for morceau in texte.lowercased().split(separator: "+") {
            let m = morceau.trimmingCharacters(in: .whitespaces)
            switch m {
            case "cmd", "command": mods |= UInt32(cmdKey)
            case "shift": mods |= UInt32(shiftKey)
            case "alt", "option", "opt": mods |= UInt32(optionKey)
            case "ctrl", "control": mods |= UInt32(controlKey)
            default:
                guard touche == nil else { return nil }
                if let k = Raccourci.nommees[m] {
                    touche = k
                } else if m.count == 1, let c = m.first {
                    touche = Raccourci.codePour(c)
                }
                guard touche != nil else { return nil }
                nom = m.uppercased()
            }
        }
        guard let t = touche else { return nil }
        var l = ""
        if mods & UInt32(controlKey) != 0 { l += "⌃" }
        if mods & UInt32(optionKey) != 0 { l += "⌥" }
        if mods & UInt32(shiftKey) != 0 { l += "⇧" }
        if mods & UInt32(cmdKey) != 0 { l += "⌘" }
        self.init(touche: UInt32(t), modificateurs: mods, libelle: l + nom)
    }

    // Code de la touche qui produit ce caractère dans la disposition active
    // (sur un clavier AZERTY, « a » n'est pas à la place du A QWERTY).
    private static func codePour(_ c: Character) -> Int? {
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
            let trouve: Int? = data.withUnsafeBytes { brut in
                guard let layout = brut.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                for code in 0..<128 {
                    var dead: UInt32 = 0
                    var len = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let err = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0,
                                             UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                             &dead, chars.count, &len, &chars)
                    if err == noErr, len == 1, String(utf16CodeUnits: chars, count: 1).lowercased() == String(c) {
                        return code
                    }
                }
                return nil
            }
            if let t = trouve { return t }
        }
        return ansi[c]
    }
}

// Enregistre des raccourcis et appelle action(id, appuyé) à chaque événement.
final class Raccourcis {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private let action: (UInt32, Bool) -> Void
    private static let signature: OSType = 0x4D52_4D52  // « MRMR »

    init(action: @escaping (UInt32, Bool) -> Void) {
        self.action = action
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, moi in
            guard let event, let moi else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let appuye = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            Unmanaged<Raccourcis>.fromOpaque(moi).takeUnretainedValue().action(id.id, appuye)
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    // Faux si le système refuse la combinaison (déjà prise par une autre app).
    @discardableResult
    func enregistrer(_ id: UInt32, _ r: Raccourci) -> Bool {
        retirer(id)
        var ref: EventHotKeyRef?
        let err = RegisterEventHotKey(r.touche, r.modificateurs, EventHotKeyID(signature: Raccourcis.signature, id: id),
                                      GetApplicationEventTarget(), 0, &ref)
        guard err == noErr, let ref else { return false }
        refs[id] = ref
        return true
    }

    func retirer(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }

    func actif(_ id: UInt32) -> Bool { refs[id] != nil }
}
