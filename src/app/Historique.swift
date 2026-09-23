import AppKit

// Sous-menu « Dernières dictées » : les 10 plus récentes de
// $MURMURE_HOME/historique.jsonl, écrit par murmure.sh (une ligne JSON par
// dictée). Le fichier est relu à chaque ouverture du sous-menu : une dictée
// y figure sans relancer l'app. Clic = copie dans le presse-papiers.
final class Historique: NSObject, NSMenuDelegate {
    private struct Entree: Decodable {
        let date: String
        let texte: String
    }

    private static let affichees = 10
    private static let longueur = 50   // caractères du début du texte

    let item = NSMenuItem(title: "Dernières dictées", action: nil, keyEquivalent: "")
    private let sousMenu = NSMenu(title: "Dernières dictées")
    private let chemin = murmureHome + "/historique.jsonl"
    private let lecteurDate = ISO8601DateFormatter()
    private let relatif: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f
    }()

    override init() {
        super.init()
        sousMenu.autoenablesItems = false
        sousMenu.delegate = self
        item.submenu = sousMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if reglage("MURMURE_HISTORY") == "0" {
            menu.addItem(ligne("Historique désactivé (MURMURE_HISTORY=0)"))
        }
        let entrees = lire()
        if entrees.isEmpty {
            menu.addItem(ligne("Aucune dictée"))
        }
        let maintenant = Date()
        for e in entrees {
            let quand = lecteurDate.date(from: e.date)
                .map { maintenant.timeIntervalSince($0) < 60 ? "à l'instant" : relatif.localizedString(for: $0, relativeTo: maintenant) }
            let titre = [resume(e.texte), quand].compactMap { $0 }.joined(separator: " — ")
            let i = NSMenuItem(title: titre, action: #selector(copier(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = e.texte
            i.toolTip = e.texte
            menu.addItem(i)
        }
        menu.addItem(.separator())
        let effacer = NSMenuItem(title: "Effacer l'historique", action: #selector(effacer), keyEquivalent: "")
        effacer.target = self
        effacer.isEnabled = !entrees.isEmpty
        menu.addItem(effacer)
    }

    // Les plus récentes d'abord ; une ligne illisible est ignorée.
    private func lire() -> [Entree] {
        guard let texte = try? String(contentsOfFile: chemin, encoding: .utf8) else { return [] }
        let decodeur = JSONDecoder()
        return texte.split(separator: "\n").reversed().lazy
            .compactMap { try? decodeur.decode(Entree.self, from: Data($0.utf8)) }
            .prefix(Historique.affichees)
            .map { $0 }
    }

    // Première ligne, espaces resserrés, tronquée à ~50 caractères.
    private func resume(_ texte: String) -> String {
        let plat = texte.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard plat.count > Historique.longueur else { return plat }
        return plat.prefix(Historique.longueur).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func ligne(_ titre: String) -> NSMenuItem {
        let i = NSMenuItem(title: titre, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc private func copier(_ sender: NSMenuItem) {
        guard let texte = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texte, forType: .string)
    }

    @objc private func effacer() {
        do {
            if FileManager.default.fileExists(atPath: chemin) {
                try Data().write(to: URL(fileURLWithPath: chemin))
            }
            journal("historique effacé")
        } catch {
            journal("historique : effacement impossible (\(error.localizedDescription))")
        }
    }
}
