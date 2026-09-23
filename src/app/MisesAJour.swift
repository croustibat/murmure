import AppKit

// Vérification des nouvelles versions : la seule requête réseau de Murmure.
// Elle lit la dernière GitHub Release publique (aucune donnée n'est envoyée)
// au plus une fois par jour, ou sur « Rechercher les mises à jour… », et la
// compare à CFBundleShortVersionString. Rien n'est téléchargé : l'entrée
// « Version X.Y.Z disponible » ouvre la page de la release, qui indique
// « git pull && ./install.sh ».
//
// MURMURE_CHECK_UPDATES=0 (environnement ou config) coupe toute requête.
// MURMURE_RELEASES_URL remplace l'adresse de l'API (tests).
// La date de la dernière requête et la version trouvée sont gardées dans
// $MURMURE_HOME/.mises-a-jour (« horodatage version url »), pour tenir la
// limite d'une requête par jour d'un lancement à l'autre.
final class MisesAJour: NSObject {
    static let adresse = "https://api.github.com/repos/croustibat/murmure/releases/latest"
    private static let intervalle: TimeInterval = 24 * 3600

    let disponible = NSMenuItem(title: "", action: #selector(ouvrirRelease), keyEquivalent: "")
    let rechercher = NSMenuItem(title: "Rechercher les mises à jour…", action: #selector(rechercherMaintenant), keyEquivalent: "")
    private let memoire = murmureHome + "/.mises-a-jour"
    private let actif = reglage("MURMURE_CHECK_UPDATES") != "0"
    private var page: URL?
    private var enCours = false
    private var minuterie: Timer?

    override init() {
        super.init()
        disponible.target = self
        rechercher.target = self
        disponible.isHidden = true
        rechercher.isHidden = !actif
    }

    func demarrer() {
        guard actif else { journal("vérification des mises à jour désactivée"); return }
        if let (version, url) = lireMemoire()?.trouve, signaler(version, url) {
            journal("mises à jour : version \(version) disponible (déjà vérifiée)")
        }
        verifierSiDu()
        // L'app reste ouverte des jours durant : on regarde chaque heure si
        // la journée est écoulée.
        minuterie = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.verifierSiDu()
        }
    }

    private func verifierSiDu() {
        let derniere = lireMemoire()?.date ?? .distantPast
        guard Date().timeIntervalSince(derniere) >= MisesAJour.intervalle else { return }
        verifier(manuel: false)
    }

    @objc private func rechercherMaintenant() { verifier(manuel: true) }

    @objc private func ouvrirRelease() {
        if let page { NSWorkspace.shared.open(page) }
    }

    // Hors ligne ou erreur : une ligne de journal, rien d'autre (sauf demande
    // explicite depuis le menu).
    private func verifier(manuel: Bool) {
        guard !enCours else { return }
        let adresse = ProcessInfo.processInfo.environment["MURMURE_RELEASES_URL"].flatMap { $0.isEmpty ? nil : $0 }
            ?? MisesAJour.adresse
        guard let url = URL(string: adresse) else { journal("mises à jour : adresse invalide \(adresse)"); return }
        enCours = true
        // La date est notée avant la requête : même en échec, une seule par jour.
        ecrireMemoire(Date(), lireMemoire()?.trouve)

        var requete = URLRequest(url: url, timeoutInterval: 15)
        requete.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        requete.setValue("Murmure/\(versionMurmure)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: requete) { donnees, reponse, erreur in
            session.finishTasksAndInvalidate()
            let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
            var trouve: (String, URL)?
            var probleme: String?
            if let erreur {
                probleme = erreur.localizedDescription
            } else if code != 200 {
                probleme = "réponse HTTP \(code)"
            } else if let donnees,
                      let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let lien = (json["html_url"] as? String).flatMap(URL.init(string:)) {
                trouve = (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, lien)
            } else {
                probleme = "réponse illisible"
            }
            DispatchQueue.main.async { self.conclure(trouve, probleme, manuel: manuel) }
        }.resume()
    }

    private func conclure(_ trouve: (String, URL)?, _ probleme: String?, manuel: Bool) {
        enCours = false
        if let probleme {
            journal("mises à jour : vérification impossible (\(probleme))")
            if manuel { alerte("Vérification impossible", "Murmure n'a pas pu joindre GitHub (\(probleme)).") }
            return
        }
        guard let (version, lien) = trouve else { return }
        ecrireMemoire(lireMemoire()?.date ?? Date(), (version, lien))
        if signaler(version, lien) {
            journal("mises à jour : version \(version) disponible (\(lien.absoluteString))")
            if manuel { ouvrirRelease() }
        } else {
            journal("mises à jour : \(versionMurmure) est à jour (dernière publiée : \(version))")
            if manuel { alerte("Murmure est à jour", "La version \(versionMurmure) est la plus récente.") }
        }
    }

    // Affiche l'entrée si la version publiée est plus récente que l'app.
    @discardableResult
    private func signaler(_ version: String, _ lien: URL) -> Bool {
        let plusRecente = MisesAJour.comparer(version, versionMurmure) == .orderedDescending
        disponible.isHidden = !plusRecente
        if plusRecente {
            disponible.title = "Version \(version) disponible"
            page = lien
        }
        return plusRecente
    }

    // Comparaison numérique composante par composante : 1.10.0 > 1.9.2,
    // 1.2 == 1.2.0. Un suffixe (« 1.2.0-beta ») est ignoré.
    static func comparer(_ a: String, _ b: String) -> ComparisonResult {
        func parties(_ v: String) -> [Int] {
            v.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        var x = parties(a), y = parties(b)
        let n = max(x.count, y.count)
        x += Array(repeating: 0, count: n - x.count)
        y += Array(repeating: 0, count: n - y.count)
        for (i, j) in zip(x, y) where i != j { return i < j ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    // Date de la dernière requête, et la version publiée trouvée alors.
    private func lireMemoire() -> (date: Date, trouve: (String, URL)?)? {
        guard let texte = try? String(contentsOfFile: memoire, encoding: .utf8) else { return nil }
        let champs = texte.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let t = champs.first.flatMap(TimeInterval.init) else { return nil }
        let trouve = champs.count >= 3 ? URL(string: champs[2]).map { (champs[1], $0) } : nil
        return (Date(timeIntervalSince1970: t), trouve)
    }

    private func ecrireMemoire(_ date: Date, _ trouve: (String, URL)?) {
        var ligne = String(Int(date.timeIntervalSince1970))
        if let (version, url) = trouve { ligne += " \(version) \(url.absoluteString)" }
        try? (ligne + "\n").write(toFile: memoire, atomically: true, encoding: .utf8)
    }

    private func alerte(_ titre: String, _ texte: String) {
        let a = NSAlert()
        a.messageText = titre
        a.informativeText = texte
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
