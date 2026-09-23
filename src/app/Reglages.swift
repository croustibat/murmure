import AppKit
import AVFoundation
import Carbon

// Fenêtre « Réglages… » : lit et écrit $MURMURE_HOME/config. Chaque contrôle
// ne réécrit que sa propre clé, au moment où on le change ; le reste du
// fichier (commentaires, clés inconnues, lignes invalides) est conservé tel
// quel. Le script relit le fichier à chaque dictée : rien à relancer, sauf
// le raccourci, que l'app réenregistre aussitôt.

// Lecture et réécriture du fichier, sans effet de bord (testables).
enum FichierConfig {
    // Valeur active d'une clé : dernière ligne « CLE=valeur » non commentée,
    // guillemets retirés, comme le lit murmure.sh.
    static func valeur(_ cle: String, dans texte: String) -> String? {
        var trouve: String?
        for ligne in texte.components(separatedBy: "\n") where cleActive(ligne) == cle {
            var v = ligne[ligne.index(after: ligne.firstIndex(of: "=")!)...]
                .trimmingCharacters(in: .whitespaces)
            if v.count >= 2, let q = v.first, q == "\"" || q == "'", v.last == q {
                v = String(v.dropFirst().dropLast())
            }
            trouve = v
        }
        return trouve.flatMap { $0.isEmpty ? nil : $0 }
    }

    // Donne à « cle » la valeur « v » (nil : la clé est commentée, le script
    // reprend sa valeur par défaut). La dernière ligne active est remplacée
    // sur place et les précédentes, qu'elle masquait, sont commentées. Sans
    // ligne active, la nouvelle ligne se place sous la ligne commentée
    // « #CLE=… » (près de sa documentation), sinon en fin de fichier.
    static func ecrire(_ cle: String, _ v: String?, dans texte: String) -> String {
        var lignes = texte.components(separatedBy: "\n")
        let actives = lignes.indices.filter { cleActive(lignes[$0]) == cle }
        for i in actives { lignes[i] = "#" + lignes[i] }
        guard let v else { return lignes.joined(separator: "\n") }
        let nouvelle = "\(cle)=\(v)"
        if let derniere = actives.last {
            lignes[derniere] = nouvelle
        } else if let modele = lignes.lastIndex(where: { cleCommentee($0) == cle }) {
            lignes.insert(nouvelle, at: modele + 1)
        } else {
            // Fin de fichier : on garde le retour à la ligne final.
            if lignes.last == "" { lignes.removeLast() }
            lignes += [nouvelle, ""]
        }
        return lignes.joined(separator: "\n")
    }

    private static func cleDe(_ l: Substring) -> String? {
        guard let eq = l.firstIndex(of: "=") else { return nil }
        let cle = l[..<eq].trimmingCharacters(in: .whitespaces)
        guard cle.hasPrefix("MURMURE_"), cle.allSatisfy({ $0 == "_" || ("A"..."Z").contains($0) }) else { return nil }
        return cle
    }

    private static func cleActive(_ ligne: String) -> String? {
        let l = ligne.trimmingCharacters(in: .whitespaces)
        return l.hasPrefix("#") ? nil : cleDe(Substring(l))
    }

    private static func cleCommentee(_ ligne: String) -> String? {
        let l = ligne.trimmingCharacters(in: .whitespaces)
        return l.hasPrefix("#") ? cleDe(l.dropFirst().drop(while: { $0 == " " })) : nil
    }
}

// Conversion d'un appui de touche en texte « cmd+shift+e », au format de
// MURMURE_SHORTCUT. Séparée de la fenêtre pour être testée sans frappe réelle.
enum EnregistreurRaccourci {
    enum Resultat: Equatable {
        case raccourci(String)
        case sansModificateur   // touche seule, ou ⇧ seul sur une lettre
        case illisible
    }

    private static let nommees: [Int: String] = [
        kVK_Space: "space", kVK_Return: "return", kVK_Tab: "tab", kVK_Escape: "escape", kVK_Delete: "delete",
        kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5",
        kVK_F6: "f6", kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9", kVK_F10: "f10",
        kVK_F11: "f11", kVK_F12: "f12", kVK_F13: "f13", kVK_F14: "f14", kVK_F15: "f15",
        kVK_F16: "f16", kVK_F17: "f17", kVK_F18: "f18", kVK_F19: "f19", kVK_F20: "f20",
    ]

    static func texte(_ e: NSEvent) -> Resultat {
        texte(code: Int(e.keyCode), modificateurs: e.modifierFlags, caractere: caractere(code: e.keyCode))
    }

    // « caractere » : ce que produit la touche sans modificateur dans la
    // disposition active (« a » sur la touche Q d'un clavier AZERTY).
    static func texte(code: Int, modificateurs: NSEvent.ModifierFlags, caractere: String?) -> Resultat {
        let f = modificateurs.intersection(.deviceIndependentFlagsMask)
        var morceaux: [String] = []
        if f.contains(.control) { morceaux.append("ctrl") }
        if f.contains(.option) { morceaux.append("alt") }
        if f.contains(.shift) { morceaux.append("shift") }
        if f.contains(.command) { morceaux.append("cmd") }

        let nom: String
        if let n = nommees[code] {
            nom = n
        } else if let c = caractere?.lowercased(), c.count == 1, c != "+",
                  !c.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 32 }) {
            nom = c
        } else {
            return .illisible
        }
        // Sans ⌘, ⌃ ni ⌥, le raccourci volerait une touche de saisie
        // (⇧ seul reste permis sur les touches de fonction).
        let fort = f.contains(.command) || f.contains(.control) || f.contains(.option)
        guard fort || (f.contains(.shift) && nom.hasPrefix("f") && nom.count > 1) else { return .sansModificateur }
        let texte = (morceaux + [nom]).joined(separator: "+")
        return Raccourci(texte: texte) == nil ? .illisible : .raccourci(texte)
    }

    // Caractère produit par la touche, sans modificateur, dans la disposition active.
    static func caractere(code: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { brut -> String? in
            guard let layout = brut.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var len = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let err = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                     OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &len, &chars)
            return err == noErr && len > 0 ? String(utf16CodeUnits: chars, count: len) : nil
        }
    }
}

final class FenetreReglages: NSObject, NSWindowDelegate {
    static let langues = ["fr", "en", "es", "de", "it", "auto"]
    private static let micDefaut = ":default"   // micro par défaut du système (ffmpeg)

    private let suspendreRaccourci: () -> Void
    private let appliquerRaccourci: () -> Bool
    private var fenetre: NSWindow?
    private let boutonRaccourci = NSButton(title: "", target: nil, action: nil)
    private let noteRaccourci = NSTextField(labelWithString: "")
    private let micro = NSPopUpButton()
    private let langue = NSPopUpButton()
    private let maintien = NSSlider(value: 600, minValue: 300, maxValue: 1500, target: nil, action: nil)
    private let valeurMaintien = NSTextField(labelWithString: "")
    private let duree = NSSlider(value: 5, minValue: 1, maxValue: 10, target: nil, action: nil)
    private let valeurDuree = NSTextField(labelWithString: "")
    private let historique = NSButton(checkboxWithTitle: "Garder les dernières dictées", target: nil, action: nil)
    private let pressePapiers = NSButton(checkboxWithTitle: "Restaurer le presse-papiers après le collage",
                                         target: nil, action: nil)
    private let demarrage = NSButton(checkboxWithTitle: "Ouvrir Murmure à l'ouverture de session", target: nil, action: nil)
    private let misesAJour = NSButton(checkboxWithTitle: "Vérifier les nouvelles versions (une fois par jour)",
                                      target: nil, action: nil)
    private var ecoute: Any?   // moniteur local pendant l'enregistrement du raccourci
    private var enAttente: [String: String] = [:]

    static var chemin: String { murmureHome + "/config" }

    // suspendre : retire le raccourci global le temps de l'enregistrement
    // (sinon il serait intercepté). appliquer : relit le config et le
    // réenregistre ; faux si le système refuse la combinaison.
    init(suspendreRaccourci: @escaping () -> Void, appliquerRaccourci: @escaping () -> Bool) {
        self.suspendreRaccourci = suspendreRaccourci
        self.appliquerRaccourci = appliquerRaccourci
    }

    func montrer() {
        if fenetre == nil { construire() }
        charger()
        NSApp.activate(ignoringOtherApps: true)
        fenetre?.makeKeyAndOrderFront(nil)
    }

    // MARK: fichier

    private func texteConfig() -> String {
        (try? String(contentsOfFile: FenetreReglages.chemin, encoding: .utf8)) ?? ""
    }

    private func lire(_ cle: String) -> String? { FichierConfig.valeur(cle, dans: texteConfig()) }

    @discardableResult
    private func ecrire(_ cle: String, _ v: String?) -> Bool {
        let texte = FichierConfig.ecrire(cle, v, dans: texteConfig())
        do {
            try texte.write(toFile: FenetreReglages.chemin, atomically: true, encoding: .utf8)
            journal("réglages : \(cle)=\(v ?? "(défaut)")")
            return true
        } catch {
            journal("réglages : écriture de \(FenetreReglages.chemin) impossible : \(error.localizedDescription)")
            return false
        }
    }

    // MARK: fenêtre

    private func construire() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 10),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Réglages de Murmure"
        w.isReleasedWhenClosed = false
        w.delegate = self

        boutonRaccourci.bezelStyle = .rounded
        boutonRaccourci.target = self
        boutonRaccourci.action = #selector(enregistrer)
        noteRaccourci.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        noteRaccourci.textColor = .secondaryLabelColor
        noteRaccourci.lineBreakMode = .byWordWrapping
        noteRaccourci.preferredMaxLayoutWidth = 340

        for (c, a) in [(micro, #selector(changerMicro)), (langue, #selector(changerLangue))] {
            c.target = self; c.action = a
        }
        for (s, a) in [(maintien, #selector(changerMaintien)), (duree, #selector(changerDuree))] {
            s.target = self; s.action = a
            s.widthAnchor.constraint(equalToConstant: 240).isActive = true
        }
        maintien.numberOfTickMarks = 25   // pas de 50 ms
        maintien.allowsTickMarkValuesOnly = true
        duree.numberOfTickMarks = 10
        duree.allowsTickMarkValuesOnly = true
        for (b, a) in [(historique, #selector(changerHistorique)), (pressePapiers, #selector(changerPressePapiers)),
                       (demarrage, #selector(changerDemarrage)), (misesAJour, #selector(changerMisesAJour))] {
            b.target = self; b.action = a
        }

        func ligne(_ vues: NSView...) -> NSStackView {
            let s = NSStackView(views: vues)
            s.orientation = .horizontal
            s.spacing = 8
            return s
        }
        let raccourci = NSStackView(views: [boutonRaccourci, noteRaccourci])
        raccourci.orientation = .vertical
        raccourci.alignment = .leading
        raccourci.spacing = 4

        let grille = NSGridView(views: [
            [etiquette("Raccourci :"), raccourci],
            [etiquette("Micro :"), micro],
            [etiquette("Langue :"), langue],
            [etiquette("Appui maintenu :"), ligne(maintien, valeurMaintien)],
            [etiquette("Durée maximale :"), ligne(duree, valeurDuree)],
            [etiquette("Historique :"), historique],
            [etiquette("Presse-papiers :"), pressePapiers],
            [etiquette("Démarrage :"), demarrage],
            [etiquette("Mises à jour :"), misesAJour],
        ])
        grille.column(at: 0).xPlacement = .trailing
        grille.rowAlignment = .firstBaseline
        grille.rowSpacing = 12
        grille.columnSpacing = 10
        grille.row(at: 0).rowAlignment = .none
        grille.cell(for: raccourci)?.yPlacement = .top
        grille.cell(atColumnIndex: 0, rowIndex: 0).yPlacement = .top

        let aide = NSTextField(wrappingLabelWithString:
            "Les réglages s'appliquent à la dictée suivante. Ils sont enregistrés dans le fichier "
            + "« config » de Murmure, qui garde vos commentaires et les autres clés.")
        aide.toolTip = NSString(string: FenetreReglages.chemin).abbreviatingWithTildeInPath
        aide.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        aide.textColor = .secondaryLabelColor
        aide.preferredMaxLayoutWidth = 470

        let pile = NSStackView(views: [grille, aide])
        pile.orientation = .vertical
        pile.alignment = .leading
        pile.spacing = 18
        pile.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        w.contentView = pile
        w.center()
        fenetre = w
    }

    private func etiquette(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.alignment = .right
        return l
    }

    // Remet chaque contrôle sur la valeur du fichier (à chaque ouverture : le
    // fichier a pu être modifié à la main entre-temps).
    private func charger() {
        let texte = texteConfig()
        func v(_ cle: String) -> String? { FichierConfig.valeur(cle, dans: texte) }

        arreterEnregistrement(reappliquer: false)
        afficherRaccourci()
        noteRaccourci.stringValue = "Cliquez puis tapez la nouvelle combinaison."
        noteRaccourci.textColor = .secondaryLabelColor

        micro.removeAllItems()
        micro.addItem(withTitle: "Par défaut du système")
        micro.lastItem?.representedObject = FenetreReglages.micDefaut
        micro.menu?.addItem(.separator())
        for nom in FenetreReglages.micros() {
            micro.addItem(withTitle: nom)
            micro.lastItem?.representedObject = nom
        }
        let actuel = v("MURMURE_DEVICE")
        if let actuel, actuel != FenetreReglages.micDefaut {
            if micro.itemArray.first(where: { $0.representedObject as? String == actuel }) == nil {
                // Index (« :1 ») ou micro débranché : gardé tel quel.
                micro.addItem(withTitle: actuel.hasPrefix(":") ? "Micro \(actuel)" : "\(actuel) (absent)")
                micro.lastItem?.representedObject = actuel
            }
            micro.selectItem(at: micro.indexOfItem(withRepresentedObject: actuel))
        } else if actuel == nil {
            // Sans réglage, le script prend le micro :0.
            micro.insertItem(withTitle: "Premier micro (:0)", at: 0)
            micro.item(at: 0)?.representedObject = nil
            micro.selectItem(at: 0)
        } else {
            micro.selectItem(at: 0)
        }

        langue.removeAllItems()
        for l in FenetreReglages.langues {
            langue.addItem(withTitle: FenetreReglages.nomLangue(l))
            langue.lastItem?.representedObject = l
        }
        let lg = v("MURMURE_LANG") ?? "fr"
        if !FenetreReglages.langues.contains(lg) {
            langue.addItem(withTitle: lg)
            langue.lastItem?.representedObject = lg
        }
        langue.selectItem(at: langue.indexOfItem(withRepresentedObject: lg))

        maintien.integerValue = min(1500, max(300, Int(v("MURMURE_HOLD_MS") ?? "") ?? 600))
        valeurMaintien.stringValue = "\(maintien.integerValue) ms"
        let secondes = Int(v("MURMURE_MAX") ?? "") ?? 300
        duree.integerValue = min(10, max(1, Int((Double(secondes) / 60).rounded())))
        valeurDuree.stringValue = FenetreReglages.libelleDuree(secondes)

        historique.state = v("MURMURE_HISTORY") == "0" ? .off : .on
        pressePapiers.state = v("MURMURE_RESTORE_CLIPBOARD") == "1" ? .on : .off
        demarrage.state = Demarrage.actif ? .on : .off
        misesAJour.state = v("MURMURE_CHECK_UPDATES") == "0" ? .off : .on
    }

    private func afficherRaccourci() {
        let r = lire("MURMURE_SHORTCUT").flatMap { Raccourci(texte: $0) } ?? Raccourci.defaut
        boutonRaccourci.title = r.libelle
    }

    static func nomLangue(_ code: String) -> String {
        switch code {
        case "fr": return "Français"
        case "en": return "Anglais"
        case "es": return "Espagnol"
        case "de": return "Allemand"
        case "it": return "Italien"
        case "auto": return "Détection automatique"
        default: return code
        }
    }

    static func libelleDuree(_ secondes: Int) -> String {
        secondes % 60 == 0 ? "\(secondes / 60) min" : "\(secondes / 60) min \(secondes % 60) s"
    }

    // Noms des entrées audio, tels que les liste ffmpeg (AVFoundation).
    static func micros() -> [String] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
                                         position: .unspecified)
            .devices.map(\.localizedName)
    }

    // MARK: actions

    @objc private func changerMicro() {
        ecrire("MURMURE_DEVICE", micro.selectedItem?.representedObject as? String)
    }

    @objc private func changerLangue() {
        if let l = langue.selectedItem?.representedObject as? String { ecrire("MURMURE_LANG", l) }
    }

    @objc private func changerMaintien() {
        valeurMaintien.stringValue = "\(maintien.integerValue) ms"
        differer("MURMURE_HOLD_MS", String(maintien.integerValue))
    }

    @objc private func changerDuree() {
        valeurDuree.stringValue = FenetreReglages.libelleDuree(duree.integerValue * 60)
        differer("MURMURE_MAX", String(duree.integerValue * 60))
    }

    // Un curseur envoie une action à chaque pas : on n'écrit que la dernière
    // valeur, un instant après (ou à la fermeture de la fenêtre).
    private func differer(_ cle: String, _ v: String) {
        enAttente[cle] = v
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(ecrireEnAttente), object: nil)
        perform(#selector(ecrireEnAttente), with: nil, afterDelay: 0.4)
    }

    @objc private func ecrireEnAttente() {
        for (cle, v) in enAttente { ecrire(cle, v) }
        enAttente = [:]
    }

    // Lu par l'app à son lancement : pris en compte au prochain démarrage.
    @objc private func changerMisesAJour() { ecrire("MURMURE_CHECK_UPDATES", misesAJour.state == .on ? "1" : "0") }
    @objc private func changerHistorique() { ecrire("MURMURE_HISTORY", historique.state == .on ? "1" : "0") }

    @objc private func changerPressePapiers() {
        ecrire("MURMURE_RESTORE_CLIPBOARD", pressePapiers.state == .on ? "1" : "0")
    }

    @objc private func changerDemarrage() {
        do {
            try Demarrage.activer(demarrage.state == .on)
        } catch {
            journal("démarrage : \(error.localizedDescription)")
        }
        demarrage.state = Demarrage.actif ? .on : .off
    }

    // MARK: raccourci

    @objc private func enregistrer() {
        guard ecoute == nil else { arreterEnregistrement(reappliquer: true); return }
        suspendreRaccourci()
        boutonRaccourci.title = "Tapez la combinaison…"
        noteRaccourci.stringValue = "Échap pour annuler."
        noteRaccourci.textColor = .secondaryLabelColor
        ecoute = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == UInt16(kVK_Escape), e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                self.arreterEnregistrement(reappliquer: true)
                return nil
            }
            switch EnregistreurRaccourci.texte(e) {
            case .raccourci(let t): self.adopter(t)
            case .sansModificateur: self.signaler("Ajoutez ⌘, ⌃ ou ⌥ : une touche seule gênerait la saisie.")
            case .illisible: self.signaler("Cette touche ne peut pas servir de raccourci.")
            }
            return nil
        }
    }

    private func arreterEnregistrement(reappliquer: Bool) {
        guard let e = ecoute else { return }
        NSEvent.removeMonitor(e)
        ecoute = nil
        if reappliquer { _ = appliquerRaccourci() }
        afficherRaccourci()
        noteRaccourci.stringValue = ""
    }

    private func signaler(_ message: String) {
        noteRaccourci.stringValue = message
        noteRaccourci.textColor = .systemRed
    }

    // Écrit la combinaison puis la réenregistre ; si le système la refuse
    // (déjà prise), l'ancienne valeur du fichier est remise.
    private func adopter(_ texte: String) {
        let ancien = lire("MURMURE_SHORTCUT")
        NSEvent.removeMonitor(ecoute!)
        ecoute = nil
        guard ecrire("MURMURE_SHORTCUT", texte) else {
            _ = appliquerRaccourci()
            afficherRaccourci()
            signaler("Impossible d'écrire \(FenetreReglages.chemin).")
            return
        }
        let libelle = Raccourci(texte: texte)?.libelle ?? texte
        if appliquerRaccourci() {
            afficherRaccourci()
            noteRaccourci.stringValue = "\(libelle) enregistré."
            noteRaccourci.textColor = .secondaryLabelColor
        } else {
            ecrire("MURMURE_SHORTCUT", ancien)
            _ = appliquerRaccourci()
            afficherRaccourci()
            signaler("\(libelle) est déjà utilisé par une autre application : raccourci inchangé.")
        }
    }

    func windowDidResignKey(_ notification: Notification) { arreterEnregistrement(reappliquer: true) }

    func windowWillClose(_ notification: Notification) {
        ecrireEnAttente()
        arreterEnregistrement(reappliquer: true)
    }
}
