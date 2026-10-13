import AppKit

// Sous-menu « Statistiques » : totaux de $MURMURE_HOME/statistiques.json,
// écrit par murmure.sh (un objet par jour local AAAA-MM-JJ : dictées, mots,
// secondes d'audio, apps ; aucun texte). Le fichier est relu à chaque
// ouverture du sous-menu ; les lignes sont en lecture seule.
final class Statistiques: NSObject, NSMenuDelegate {
    struct Jour: Decodable {
        let dictees: Int
        let mots: Int
        let secondes: Double
        let apps: [String: Int]?
    }

    // Vitesse de frappe de référence pour le temps gagné : une constante, pas un réglage.
    private static let motsParMinuteAuClavier = 40

    let item = NSMenuItem(title: "Statistiques", action: nil, keyEquivalent: "")
    private let sousMenu = NSMenu(title: "Statistiques")
    private let chemin = murmureHome + "/statistiques.json"
    private static let chiffres: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
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
        var lignes = Statistiques.lignes(lire(), aujourdhui: Date(), nom: Statistiques.nomApp)
        if reglage("MURMURE_HISTORY") == "0" {
            lignes.insert("Statistiques désactivées (MURMURE_HISTORY=0)", at: 0)
        }
        for titre in lignes {
            let i = NSMenuItem(title: titre, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
    }

    // Fichier absent ou illisible : aucune donnée (murmure.sh le recompte
    // depuis l'historique à la prochaine dictée).
    private func lire() -> [String: Jour] {
        guard let data = FileManager.default.contents(atPath: chemin) else { return [:] }
        return (try? JSONDecoder().decode([String: Jour].self, from: data)) ?? [:]
    }

    // Lignes du sous-menu ; `nom` donne le nom affiché d'un bundle id.
    static func lignes(_ jours: [String: Jour], aujourdhui: Date, nom: (String) -> String) -> [String] {
        let dictees = jours.values.reduce(0) { $0 + $1.dictees }
        guard dictees > 0 else { return ["Aucune dictée"] }
        let mots = jours.values.reduce(0) { $0 + $1.mots }
        let minutes = jours.values.reduce(0) { $0 + $1.secondes } / 60
        var lignes = ["\(nombre(mots, "mot dicté", "mots dictés")) · \(nombre(dictees, "dictée", "dictées"))"]
        if minutes > 0 {
            lignes.append("\(nombre(Int((Double(mots) / minutes).rounded()), "mot/min", "mots/min")) en moyenne")
        }
        let gagnees = Int((Double(mots) / Double(motsParMinuteAuClavier) - minutes).rounded())
        if gagnees >= 1 {
            let (h, m) = (gagnees / 60, gagnees % 60)
            let duree = h > 0 ? "\(chiffres.string(from: h as NSNumber) ?? "\(h)") h \(String(format: "%02d", m))" : "\(m) min"
            let accord = (h > 0 ? h : m) > 1 ? "gagnées" : "gagnée"
            lignes.append("≈ \(duree) \(accord) (contre \(motsParMinuteAuClavier) mots/min au clavier)")
        }

        let calendrier = Calendar(identifier: .gregorian)
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withFullDate]
        format.timeZone = calendrier.timeZone
        let jour = { (d: Date) in jours[format.string(from: d)] }
        let veille = { (d: Date) in calendrier.date(byAdding: .day, value: -1, to: d)! }
        lignes.append("Aujourd'hui : \(nombre(jour(aujourdhui)?.mots ?? 0, "mot", "mots"))")
        // Jours consécutifs jusqu'à aujourd'hui, ou jusqu'à hier si rien n'a
        // encore été dicté aujourd'hui.
        var d = (jour(aujourdhui)?.dictees ?? 0) > 0 ? aujourdhui : veille(aujourdhui)
        var serie = 0
        while (jour(d)?.dictees ?? 0) > 0 { serie += 1; d = veille(d) }
        if serie >= 2 { lignes.append("Série : \(nombre(serie, "jour", "jours"))") }

        var parApp: [String: Int] = [:]
        for j in jours.values { parApp.merge(j.apps ?? [:], uniquingKeysWith: +) }
        let premieres = parApp.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(3).map { nom($0.key) }
        if !premieres.isEmpty { lignes.append("Surtout dans : " + premieres.joined(separator: ", ")) }
        return lignes
    }

    // « 1 mot », « 5 623 mots ».
    private static func nombre(_ n: Int, _ un: String, _ plusieurs: String) -> String {
        "\(chiffres.string(from: n as NSNumber) ?? "\(n)") \(n > 1 ? plusieurs : un)"
    }

    // Nom affiché de l'app, sinon son bundle id (app désinstallée). Sans le
    // « .app » que displayName garde quand le Finder affiche les extensions.
    private static func nomApp(_ bundle: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        let nom = FileManager.default.displayName(atPath: url.path)
        return nom.hasSuffix(".app") ? String(nom.dropLast(4)) : nom
    }
}
