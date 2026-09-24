import AppKit

// Icône et menu de la barre des menus. L'état est lu dans le fichier « status »
// écrit par murmure.sh, comme le fait la pastille : absent = prêt,
// « recording » = écoute, « transcribing … » ou « pasting » = transcription.
final class Barre: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Etat { case pret, ecoute, transcription }
    private static let idDictee: UInt32 = 1
    private static let idEchap: UInt32 = 2

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let ligneEtat = NSMenuItem(title: "Prêt", action: nil, keyEquivalent: "")
    private let ligneRaccourci = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let bascule = NSMenuItem(title: "Démarrer la dictée", action: #selector(basculer), keyEquivalent: "")
    private let demarrage = NSMenuItem(title: "Ouvrir au démarrage", action: #selector(changerDemarrage), keyEquivalent: "")
    private let historique = Historique()
    private let misesAJour = MisesAJour()
    private let autorisations = Autorisations()
    private var raccourcis: Raccourcis!
    private var etat: Etat?
    private var enfonce = false   // touche du raccourci actuellement enfoncée
    private var surveillance: DispatchSourceFileSystemObject?
    private var releve: Timer?
    private lazy var reglages = FenetreReglages(suspendreRaccourci: { [unowned self] in raccourcis.retirer(Barre.idDictee) },
                                                appliquerRaccourci: { [unowned self] in enregistrerRaccourci() })

    func applicationDidFinishLaunching(_ note: Notification) {
        raccourcis = Raccourcis { [weak self] id, appuye in self?.touche(id, appuye) }
        construireMenu()
        enregistrerRaccourci()
        surveiller()
        lireEtat()
        journal("Murmure \(versionMurmure) prête (\(murmureHome))")
        misesAJour.demarrer()
        autorisations.changement = { [weak self] in self?.dessinerIcone() }
        autorisations.demarrer()
    }

    private func construireMenu() {
        ligneEtat.isEnabled = false
        ligneRaccourci.isEnabled = false
        bascule.target = self
        demarrage.target = self
        let dernieres = historique.item
        let reglages = NSMenuItem(title: "Réglages…", action: #selector(ouvrirReglages), keyEquivalent: ",")
        reglages.target = self
        let journalItem = NSMenuItem(title: "Ouvrir le journal", action: #selector(ouvrirJournal), keyEquivalent: "")
        journalItem.target = self
        let versionItem = NSMenuItem(title: "Murmure \(versionMurmure)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        let quitter = NSMenuItem(title: "Quitter Murmure", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for i in [autorisations.accessibilite, autorisations.micro, autorisations.relancer, autorisations.separateur,
                  ligneEtat, ligneRaccourci, bascule, .separator(), dernieres, .separator(),
                  reglages, demarrage, journalItem, .separator(), misesAJour.disponible, versionItem, misesAJour.rechercher, quitter] {
            menu.addItem(i)
        }
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
    }

    // MURMURE_SHORTCUT (environnement ou config), sinon ⌘⇧E.
    @discardableResult
    private func enregistrerRaccourci() -> Bool {
        var r = Raccourci.defaut
        if let texte = reglage("MURMURE_SHORTCUT") {
            if let lu = Raccourci(texte: texte) {
                r = lu
            } else {
                journal("MURMURE_SHORTCUT illisible (« \(texte) ») : \(r.libelle) à la place")
            }
        }
        if raccourcis.enregistrer(Barre.idDictee, r) {
            ligneRaccourci.title = "Raccourci : \(r.libelle)"
            journal("raccourci \(r.libelle) enregistré")
            return true
        }
        ligneRaccourci.title = "Raccourci \(r.libelle) indisponible"
        journal("raccourci \(r.libelle) refusé par le système (déjà utilisé ?)")
        return false
    }

    private func touche(_ id: UInt32, _ appuye: Bool) {
        // Un seul press par appui physique, même si le système répétait
        // l'événement pendant un maintien (chaque press bascule l'écoute).
        if id == Barre.idDictee {
            guard appuye != enfonce else { return }
            enfonce = appuye
        }
        switch (id, appuye) {
        case (Barre.idDictee, true): lancer("press") { self.lireEtat() }
        case (Barre.idDictee, false): lancer("release") { self.lireEtat() }
        case (Barre.idEchap, true): lancer("cancel") { self.lireEtat() }
        default: break
        }
    }

    // Le dossier d'état signale la création et la suppression de « status » ;
    // ses réécritures (écoute → transcription) sont relevées par une
    // minuterie qui ne tourne que pendant une dictée.
    private func surveiller() {
        let fd = open(stateDir, O_EVTONLY)
        guard fd >= 0 else { journal("surveillance de \(stateDir) impossible"); return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in self?.lireEtat() }
        s.setCancelHandler { close(fd) }
        s.resume()
        surveillance = s
    }

    private func lireEtat() {
        let brut = (try? String(contentsOfFile: statusPath, encoding: .utf8)) ?? ""
        let mot = brut.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let nouvel: Etat = mot == "recording" ? .ecoute
            : (mot == "transcribing" || mot == "pasting") ? .transcription : .pret

        if nouvel == .pret {
            releve?.invalidate(); releve = nil
        } else if releve == nil {
            releve = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.lireEtat() }
        }
        guard nouvel != etat else { return }
        if nouvel == .pret && etat != nil { autorisations.verifier() }   // collage refusé ?
        etat = nouvel

        // Échap n'est intercepté que pendant l'écoute : le reste du temps, il
        // garde son rôle dans toutes les applications.
        if nouvel == .ecoute {
            if !raccourcis.enregistrer(Barre.idEchap, Raccourci.echap) { journal("Échap indisponible") }
        } else {
            raccourcis.retirer(Barre.idEchap)
        }

        switch nouvel {
        case .pret:
            ligneEtat.title = "Prêt"; bascule.title = "Démarrer la dictée"
        case .ecoute:
            ligneEtat.title = "Écoute…"; bascule.title = "Arrêter et transcrire"
        case .transcription:
            ligneEtat.title = "Transcription…"; bascule.title = "Démarrer la dictée"
        }
        bascule.isEnabled = nouvel != .transcription
        dessinerIcone()
    }

    // Au repos, une autorisation manquante marque l'onde d'un point d'exclamation.
    private func dessinerIcone() {
        let symbole: String
        switch etat ?? .pret {
        case .pret: symbole = autorisations.manque ? "waveform.badge.exclamationmark" : "waveform"
        case .ecoute: symbole = "waveform.circle.fill"
        case .transcription: symbole = "ellipsis.circle"
        }
        let image = NSImage(systemSymbolName: symbole, accessibilityDescription: "Murmure — \(ligneEtat.title)")
        image?.isTemplate = true
        item.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        demarrage.state = Demarrage.actif ? .on : .off
        autorisations.verifier()
        lireEtat()
    }

    @objc private func basculer() { lancer("toggle") { self.lireEtat() } }

    @objc private func changerDemarrage() {
        do {
            try Demarrage.activer(!Demarrage.actif)
        } catch {
            journal("démarrage : \(error.localizedDescription)")
        }
        demarrage.state = Demarrage.actif ? .on : .off
    }

    @objc private func ouvrirReglages() { reglages.montrer() }

    @objc private func ouvrirJournal() {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
}
