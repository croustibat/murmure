import AppKit
import CryptoKit
import UniformTypeIdentifiers

// Modèle Whisper : une app installée par DMG n'a pas install.sh pour le
// télécharger, elle le fait elle-même au premier lancement.
// - Nom, révision, empreinte et taille : app/modele.conf, copié dans les
//   ressources du bundle et lu aussi par install.sh. Mêmes surcharges
//   d'environnement (MURMURE_MODEL_URL, _SHA256, _SIZE, _NAME) pour les tests.
// - Comme install.sh : téléchargement vers « .part » avec reprise, empreinte
//   SHA-256 vérifiée, puis renommage : un fichier tronqué ou corrompu ne passe
//   jamais pour le modèle.
// - Tant qu'il manque, le menu l'annonce en tête et le raccourci ouvre la
//   fenêtre au lieu de lancer une capture.
// - Un modèle déjà présent n'ouvre jamais la fenêtre : sa taille suffit au
//   lancement, son empreinte est vérifiée une fois en arrière-plan, puis
//   retenue avec la taille et la date du fichier ($MURMURE_HOME/.modele-verifie).
// - Préchauffage : le premier lancement d'une nouvelle version de
//   whisper-cli compile ses noyaux Metal (17 à 54 s sur M4). Il est fait une
//   fois en arrière-plan, sur une seconde de silence, quand le modèle est
//   prêt et à chaque nouvelle version ($MURMURE_HOME/.prechauffage) : la
//   première dictée ne l'attend pas, et aucune n'est bloquée pendant ce temps.
// MURMURE_MODEL (chemin complet, comme pour murmure.sh) : modèle fourni à la
// main, jamais téléchargé ni vérifié.
final class Modele: NSObject {
    private enum Phase {
        case attente(String?, reessayer: Bool)   // message en rouge
        case telechargement
        case verification   // empreinte du fichier reçu ou choisi
        case preparation
        case pret
    }

    let ligne = NSMenuItem(title: "Modèle à télécharger…", action: #selector(montrer), keyEquivalent: "")
    let separateur = NSMenuItem.separator()
    // Vrai tant que le modèle n'est pas en place : le raccourci ouvre la fenêtre.
    private(set) var manquant = false

    private let constantes = ConstantesModele.lire()
    private let impose = ProcessInfo.processInfo.environment["MURMURE_MODEL"].flatMap { $0.isEmpty ? nil : $0 }
    private lazy var chemin = impose ?? murmureHome + "/models/" + constantes.nom
    private var part: String { chemin + ".part" }
    private let memoireVerification = murmureHome + "/.modele-verifie"
    private let memoirePrechauffage = murmureHome + "/.prechauffage"
    private var phase = Phase.pret
    private var telechargement: Telechargement?
    private var relance = false   // nouveau téléchargement complet déjà tenté
    private var echantillons: [(Date, Int64)] = []   // débit des 5 dernières secondes
    private var recus: Int64 = 0
    private var total: Int64?
    private var prechauffage: Process?

    private var fenetre: NSWindow?
    private let titre = NSTextField(labelWithString: "")
    private let texte = NSTextField(wrappingLabelWithString: "")
    private let barre = NSProgressIndicator()
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let principal = NSButton(title: "", target: nil, action: nil)
    private let secondaire = NSButton(title: "", target: nil, action: nil)
    private let importer = NSButton(title: "J'ai déjà le fichier…", target: nil, action: nil)

    override init() {
        super.init()
        ligne.target = self
        ligne.isHidden = true
        separateur.isHidden = true
    }

    func demarrer() {
        if impose != nil {
            journal("modèle : \(chemin) (MURMURE_MODEL), ni téléchargé ni vérifié")
            if FileManager.default.fileExists(atPath: chemin) { prechauffer() }
            return
        }
        guard !constantes.nom.isEmpty else { journal("modèle : modele.conf illisible, rien à vérifier"); return }
        try? FileManager.default.createDirectory(atPath: (chemin as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: chemin) {
            let taille = Modele.taille(chemin)
            if let attendue = constantes.taille, taille != attendue {
                journal("modèle : taille inattendue (\(taille) octets au lieu de \(attendue))")
                if taille < attendue && !FileManager.default.fileExists(atPath: part) {
                    rename(chemin, part)   // tronqué : le téléchargement reprendra là où il s'est arrêté
                } else {
                    try? FileManager.default.removeItem(atPath: chemin)
                }
            } else if taille == 0 {
                try? FileManager.default.removeItem(atPath: chemin)
            }
        }
        if FileManager.default.fileExists(atPath: chemin) {
            verifierEnArrierePlan()
        } else {
            journal("modèle absent (\(chemin)) : fenêtre de téléchargement")
            passer(.attente(nil, reessayer: false))
            montrer()
        }
    }

    @objc func montrer() {
        if fenetre == nil { construire() }
        afficher()
        NSApp.activate(ignoringOtherApps: true)
        fenetre?.makeKeyAndOrderFront(nil)
    }

    private func passer(_ p: Phase) {
        phase = p
        switch p {
        case .attente, .telechargement, .verification: manquant = true
        case .preparation, .pret: manquant = false
        }
        afficher()
    }

    // MARK: modèle présent au lancement

    // Pendant la vérification, le modèle est tenu pour bon : la dictée reste
    // possible. Corrompu, il est supprimé et la fenêtre propose de le retélécharger.
    private func verifierEnArrierePlan() {
        guard let attendue = constantes.sha256 else { prechauffer(); return }
        if Modele.lire(memoireVerification) == cleVerification() { prechauffer(); return }
        journal("modèle : vérification de l'empreinte de \(chemin)…")
        let chemin = chemin
        DispatchQueue.global(qos: .utility).async {
            let calculee = try? Modele.sha256(chemin)
            DispatchQueue.main.async {
                if calculee == attendue {
                    journal("modèle : empreinte vérifiée")
                    self.retenirVerification()
                    self.prechauffer()
                } else if calculee == nil {
                    journal("modèle : lecture de \(chemin) impossible, vérification remise au prochain lancement")
                } else {
                    journal("modèle : empreinte incorrecte, modèle corrompu supprimé")
                    try? FileManager.default.removeItem(atPath: chemin)
                    try? FileManager.default.removeItem(atPath: self.memoireVerification)
                    self.passer(.attente("Le modèle présent était endommagé (empreinte incorrecte) : il a été supprimé.",
                                         reessayer: false))
                    self.montrer()
                }
            }
        }
    }

    // Taille, date et empreinte attendue : un fichier modifié ou une autre
    // empreinte attendue redemandent une vérification.
    private func cleVerification() -> String {
        let date = Modele.date(chemin).map { String(Int($0.timeIntervalSince1970 * 1000)) } ?? "?"
        return "\(Modele.taille(chemin)) \(date) \(constantes.sha256 ?? "-")"
    }

    private func retenirVerification() {
        try? (cleVerification() + "\n").write(toFile: memoireVerification, atomically: true, encoding: .utf8)
    }

    // MARK: téléchargement

    @objc private func telechargerDepuisFenetre() {
        relance = false
        telecharger()
    }

    private func telecharger() {
        guard let url = constantes.url else {
            passer(.attente("Adresse du modèle invalide : voir modele.conf.", reessayer: false))
            return
        }
        let t = Telechargement(url: url, vers: part, taille: constantes.taille)
        t.progression = { [weak self] recus, total in self?.progresser(recus, total) }
        t.fin = { [weak self] fin in self?.terminer(fin) }
        telechargement = t
        echantillons = []
        recus = Modele.taille(part)
        total = constantes.taille
        passer(.telechargement)
        journal("modèle : téléchargement de \(url.absoluteString) (\(recus) octets déjà reçus)")
        t.demarrer()
    }

    @objc private func annuler() { telechargement?.annuler() }

    private func progresser(_ recus: Int64, _ total: Int64?) {
        self.recus = recus
        self.total = total ?? constantes.taille
        let maintenant = Date()
        echantillons.append((maintenant, recus))
        echantillons.removeAll { maintenant.timeIntervalSince($0.0) > 5 }
        afficher()
    }

    private var debit: Double? {
        guard let a = echantillons.first, let b = echantillons.last else { return nil }
        let duree = b.0.timeIntervalSince(a.0)
        return duree >= 1 ? Double(b.1 - a.1) / duree : nil
    }

    private func terminer(_ fin: Telechargement.Fin) {
        telechargement = nil
        let deja = Modele.taille(part)
        switch fin {
        case .annule:
            journal("modèle : téléchargement annulé (\(deja) octets conservés)")
            passer(.attente(nil, reessayer: false))
        case .echec(let probleme):
            journal("modèle : téléchargement interrompu (\(probleme), \(deja) octets conservés)")
            let conserve = deja > 0 ? " Les \(Modele.mo(deja)) déjà reçus sont conservés." : ""
            passer(.attente("Le téléchargement s'est interrompu : \(probleme).\(conserve)", reessayer: true))
        case .termine:
            journal("modèle : téléchargement terminé (\(deja) octets)")
            installer(part, telecharge: true)
        }
    }

    // MARK: fichier déjà téléchargé

    @objc private func choisirFichier() {
        guard let w = fenetre else { return }
        let p = NSOpenPanel()
        p.message = "Choisissez le fichier \(constantes.nom)"
        p.prompt = "Utiliser ce fichier"
        p.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        p.beginSheetModal(for: w) { reponse in
            guard reponse == .OK, let url = p.url else { return }
            self.copier(url.path)
        }
    }

    private func copier(_ source: String) {
        let taille = Modele.taille(source)
        if let attendue = constantes.taille, taille != attendue {
            journal("modèle : \(source) refusé (\(taille) octets au lieu de \(attendue))")
            passer(.attente("Ce fichier ne fait pas la taille attendue (\(Modele.mo(taille)) au lieu de "
                            + "\(Modele.mo(attendue))) : ce n'est pas \(constantes.nom).", reessayer: false))
            return
        }
        journal("modèle : copie de \(source)")
        passer(.verification)
        let copie = chemin + ".copie"
        DispatchQueue.global(qos: .userInitiated).async {
            try? FileManager.default.removeItem(atPath: copie)
            do {
                try FileManager.default.copyItem(atPath: source, toPath: copie)
                DispatchQueue.main.async { self.installer(copie, telecharge: false) }
            } catch {
                DispatchQueue.main.async {
                    journal("modèle : copie impossible (\(error.localizedDescription))")
                    self.passer(.attente("Copie impossible : \(error.localizedDescription)", reessayer: false))
                }
            }
        }
    }

    // MARK: installation

    // Empreinte vérifiée hors du fil principal, puis renommage atomique (même
    // dossier). Un fichier reçu corrompu est supprimé et retéléchargé une fois
    // en entier, comme le fait install.sh.
    private func installer(_ source: String, telecharge: Bool) {
        passer(.verification)
        let attendue = constantes.sha256
        DispatchQueue.global(qos: .userInitiated).async {
            let calculee = attendue == nil ? nil : (try? Modele.sha256(source))
            DispatchQueue.main.async {
                if let attendue {
                    guard let calculee else {
                        journal("modèle : lecture de \(source) impossible")
                        self.passer(.attente("Lecture du fichier impossible pour vérifier son empreinte.", reessayer: telecharge))
                        return
                    }
                    guard calculee == attendue else {
                        journal("modèle : empreinte incorrecte (\(calculee)), \(source) supprimé")
                        try? FileManager.default.removeItem(atPath: source)
                        if telecharge && !self.relance {
                            self.relance = true
                            journal("modèle : nouveau téléchargement complet")
                            self.telecharger()
                        } else if telecharge {
                            self.passer(.attente("Le fichier reçu est corrompu (empreinte incorrecte) : il a été supprimé.",
                                                 reessayer: true))
                        } else {
                            self.passer(.attente("Ce fichier n'est pas \(self.constantes.nom) : son empreinte ne "
                                                 + "correspond pas. Il n'a pas été copié.", reessayer: false))
                        }
                        return
                    }
                } else {
                    journal("modèle : aucune empreinte connue pour \(self.constantes.nom), intégrité non vérifiée")
                }
                guard rename(source, self.chemin) == 0 else {
                    let erreur = String(cString: strerror(errno))
                    journal("modèle : \(source) → \(self.chemin) impossible (\(erreur))")
                    self.passer(.attente("Installation du modèle impossible : \(erreur).", reessayer: telecharge))
                    return
                }
                journal("modèle : installé (\(self.chemin))")
                self.retenirVerification()
                self.prechauffer()
            }
        }
    }

    // MARK: préchauffage

    // whisper-cli du bundle, ou MURMURE_WHISPER comme pour murmure.sh.
    private var whisper: String {
        reglage("MURMURE_WHISPER") ?? Bundle.main.bundlePath + "/Contents/Helpers/whisper-cli"
    }

    private func prechauffer() {
        guard prechauffage == nil else { return }
        let whisper = whisper
        guard FileManager.default.isExecutableFile(atPath: whisper) else {
            journal("préchauffage : whisper-cli introuvable (\(whisper))")
            passer(.pret)
            return
        }
        // Une nouvelle version de l'app ou de whisper-cli change la clé.
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let date = Modele.date(whisper).map { String(Int($0.timeIntervalSince1970)) } ?? "?"
        let cle = "\(versionMurmure) \(build) \(Modele.taille(whisper)) \(date) \(whisper)"
        if Modele.lire(memoirePrechauffage) == cle { passer(.pret); return }

        let wav = stateDir + "/prechauffage.wav"
        let erreurs = stateDir + "/prechauffage.err"
        FileManager.default.createFile(atPath: wav, contents: Modele.silence(secondes: 1))
        FileManager.default.createFile(atPath: erreurs, contents: nil)
        // Lancé par un bash, comme murmure.sh lance whisper-cli : macOS ne
        // réutilise les noyaux Metal compilés qu'entre processus lancés de
        // la même façon (mesuré : préchauffé directement par l'app, la
        // dictée suivante recompilait tout, 25 s au lieu de 2).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "\"$@\"; exit $?", "_", whisper, "-m", chemin, "-f", wav, "--no-timestamps", "--no-prints"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle(forWritingAtPath: erreurs)
        let debut = Date()
        p.terminationHandler = { p in
            DispatchQueue.main.async {
                let duree = String(format: "%.1f", Date().timeIntervalSince(debut))
                if p.terminationStatus == 0 {
                    journal("préchauffage : whisper-cli prêt en \(duree) s")
                    try? (cle + "\n").write(toFile: self.memoirePrechauffage, atomically: true, encoding: .utf8)
                } else {
                    let sortie = (try? String(contentsOfFile: erreurs, encoding: .utf8)) ?? ""
                    journal("préchauffage : échec de whisper-cli (code \(p.terminationStatus), \(duree) s) :\n"
                            + sortie.split(separator: "\n").suffix(5).joined(separator: "\n"))
                }
                try? FileManager.default.removeItem(atPath: wav)
                try? FileManager.default.removeItem(atPath: erreurs)
                self.prechauffage = nil
                self.passer(.pret)
            }
        }
        do {
            try p.run()
        } catch {
            journal("préchauffage : lancement de \(whisper) impossible (\(error.localizedDescription))")
            passer(.pret)
            return
        }
        prechauffage = p
        journal("préchauffage de whisper-cli (\(whisper))…")
        passer(.preparation)
    }

    // WAV 16 kHz mono 16 bits, muet.
    static func silence(secondes: Int) -> Data {
        let n = UInt32(32000 * secondes)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + n); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(n)
        d.append(Data(count: Int(n)))
        return d
    }

    // MARK: fenêtre

    private func construire() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 10),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Murmure"
        w.isReleasedWhenClosed = false

        let largeur: CGFloat = 360
        titre.font = .boldSystemFont(ofSize: 15)
        texte.preferredMaxLayoutWidth = largeur
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.preferredMaxLayoutWidth = largeur
        barre.style = .bar
        barre.minValue = 0
        barre.maxValue = 1
        barre.widthAnchor.constraint(equalToConstant: largeur).isActive = true
        for (b, a) in [(principal, #selector(actionPrincipale)), (secondaire, #selector(annuler)),
                       (importer, #selector(choisirFichier))] {
            b.bezelStyle = .rounded
            b.target = self
            b.action = a
        }
        principal.keyEquivalent = "\r"

        let icone = NSImageView(image: NSApp.applicationIconImage)
        icone.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icone.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let espace = NSView()
        espace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let boutons = NSStackView(views: [importer, espace, secondaire, principal])
        boutons.orientation = .horizontal
        boutons.widthAnchor.constraint(equalToConstant: largeur).isActive = true

        let colonne = NSStackView(views: [titre, texte, barre, detail, boutons])
        colonne.orientation = .vertical
        colonne.alignment = .leading
        colonne.spacing = 10
        colonne.setCustomSpacing(18, after: detail)
        let pile = NSStackView(views: [icone, colonne])
        pile.orientation = .horizontal
        pile.alignment = .top
        pile.spacing = 16
        pile.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 24)
        w.contentView = pile
        w.center()
        fenetre = w
    }

    @objc private func actionPrincipale() {
        switch phase {
        case .attente: telechargerDepuisFenetre()
        case .preparation, .pret: fenetre?.close()
        case .telechargement, .verification: break
        }
    }

    // Met la fenêtre (si elle a été ouverte) et la ligne du menu à jour.
    private func afficher() {
        let tailleModele = constantes.taille.map(Modele.arrondi)
        switch phase {
        case .attente: ligne.title = "Modèle à télécharger…"
        case .telechargement:
            ligne.title = total.map { "Téléchargement du modèle… \(Int(Double(recus) * 100 / Double(max($0, 1)))) %" }
                ?? "Téléchargement du modèle…"
        case .verification: ligne.title = "Vérification du modèle…"
        case .preparation: ligne.title = "Préparation…"
        case .pret: break
        }
        if case .pret = phase { ligne.isHidden = true } else { ligne.isHidden = false }
        separateur.isHidden = ligne.isHidden

        guard fenetre != nil else { return }
        titre.stringValue = "Télécharger le modèle de transcription"
        texte.stringValue = "Murmure transcrit votre voix avec Whisper, un modèle qui tourne entièrement sur ce "
            + "Mac : rien de ce que vous dictez n'en sort. Il se télécharge une seule fois, avant la première dictée."
        detail.textColor = .secondaryLabelColor
        barre.stopAnimation(nil)
        barre.isIndeterminate = false
        for v in [barre, detail, principal, secondaire, importer] as [NSView] { v.isHidden = true }

        switch phase {
        case .attente(let message, let reessayer):
            let deja = Modele.taille(part)
            if deja > 0, let t = constantes.taille {
                barre.doubleValue = Double(deja) / Double(max(t, 1))
                barre.isHidden = false
            }
            if let message {
                detail.stringValue = message
                detail.textColor = .systemRed
                detail.isHidden = false
            } else if deja > 0 {
                detail.stringValue = "\(Modele.mo(deja)) déjà reçus : le téléchargement reprendra là où il s'est arrêté."
                detail.isHidden = false
            }
            principal.title = reessayer ? "Réessayer"
                : deja > 0 ? "Reprendre le téléchargement"
                : tailleModele.map { "Télécharger (\($0))" } ?? "Télécharger"
            principal.isHidden = false
            importer.isHidden = false
        case .telechargement:
            if let total {
                barre.doubleValue = Double(recus) / Double(max(total, 1))
                var morceaux = ["\(Modele.mo(recus)) sur \(Modele.mo(total))"]
                if let debit, debit > 0 {
                    morceaux.append("\(Modele.mo(Int64(debit)))/s")
                    morceaux.append("encore environ \(Modele.duree(Double(total - recus) / debit))")
                }
                detail.stringValue = morceaux.joined(separator: " — ")
            } else {
                barre.isIndeterminate = true
                barre.startAnimation(nil)
                detail.stringValue = "\(Modele.mo(recus)) reçus"
            }
            barre.isHidden = false
            detail.isHidden = false
            secondaire.title = "Annuler"
            secondaire.isHidden = false
        case .verification:
            barre.isIndeterminate = true
            barre.startAnimation(nil)
            barre.isHidden = false
            detail.stringValue = "Vérification de l'empreinte du modèle…"
            detail.isHidden = false
        case .preparation:
            titre.stringValue = "Modèle installé"
            texte.stringValue = "Murmure prépare la transcription sur ce Mac : une seule fois, moins d'une minute. "
                + "Vous pouvez déjà dicter."
            barre.isIndeterminate = true
            barre.startAnimation(nil)
            barre.isHidden = false
            detail.stringValue = "Préparation…"
            detail.isHidden = false
            principal.title = "Fermer"
            principal.isHidden = false
        case .pret:
            let raccourci = reglage("MURMURE_SHORTCUT").flatMap { Raccourci(texte: $0) } ?? Raccourci.defaut
            titre.stringValue = "Murmure est prêt"
            texte.stringValue = "Dictez avec \(raccourci.libelle) : appuyez, parlez, puis appuyez à nouveau. "
                + "L'icône de la barre des menus donne l'état et les réglages."
            principal.title = "Fermer"
            principal.isHidden = false
        }
    }

    // MARK: outils

    static func taille(_ chemin: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: chemin))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func date(_ chemin: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: chemin))?[.modificationDate] as? Date
    }

    static func lire(_ chemin: String) -> String? {
        (try? String(contentsOfFile: chemin, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Lu par blocs de 8 Mo : le modèle ne tient pas en mémoire d'un coup.
    static func sha256(_ chemin: String) throws -> String {
        guard let f = FileHandle(forReadingAtPath: chemin) else { throw CocoaError(.fileReadNoSuchFile) }
        defer { try? f.close() }
        var h = SHA256()
        while let bloc = try autoreleasepool(invoking: { try f.read(upToCount: 8 << 20) }), !bloc.isEmpty {
            h.update(data: bloc)
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // « 123 Mo », « 4,2 Mo » (Mo de 2^20 octets, comme install.sh).
    static func mo(_ octets: Int64) -> String {
        let v = Double(octets) / 1_048_576
        return v < 10 ? String(format: "%.1f Mo", v).replacingOccurrences(of: ".", with: ",") : "\(Int(v.rounded())) Mo"
    }

    // Taille annoncée sur le bouton : « 550 Mo ».
    static func arrondi(_ octets: Int64) -> String {
        let v = Double(octets) / 1_048_576
        return v < 100 ? mo(octets) : "\(Int((v / 10).rounded()) * 10) Mo"
    }

    static func duree(_ secondes: Double) -> String {
        secondes < 60 ? "\(max(5, Int((secondes / 5).rounded()) * 5)) s" : "\(Int((secondes / 60).rounded())) min"
    }
}

// Constantes du modèle : app/modele.conf (ressource du bundle), puis les
// surcharges d'environnement, avec les mêmes règles qu'install.sh.
struct ConstantesModele {
    var nom: String
    var url: URL?
    var sha256: String?   // nil : intégrité non vérifiable (autre modèle)
    var taille: Int64?

    static func lire() -> ConstantesModele {
        var conf: [String: String] = [:]
        if let chemin = Bundle.main.path(forResource: "modele", ofType: "conf"),
           let texte = try? String(contentsOfFile: chemin, encoding: .utf8) {
            for ligne in texte.split(separator: "\n") {
                let l = ligne.trimmingCharacters(in: .whitespaces)
                guard !l.hasPrefix("#"), let eq = l.firstIndex(of: "=") else { continue }
                conf[String(l[..<eq])] = l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            }
        } else {
            journal("modèle : modele.conf absent des ressources de l'app")
        }
        let env = ProcessInfo.processInfo.environment.filter { !$0.value.isEmpty }
        let defaut = conf["MODEL_NAME"] ?? ""
        let nom = env["MURMURE_MODEL_NAME"] ?? defaut
        var adresse = env["MURMURE_MODEL_URL"]
        if adresse == nil, let depot = conf["MODEL_REPO"], let rev = conf["MODEL_REV"] {
            adresse = "\(depot)/\(rev)/\(nom)"
        }
        // Empreinte et taille ne valent que pour le modèle de modele.conf.
        let connu = nom == defaut
        return ConstantesModele(
            nom: nom,
            url: adresse.flatMap(URL.init(string:)),
            sha256: (env["MURMURE_MODEL_SHA256"] ?? (connu ? conf["MODEL_SHA256"] : nil))?.lowercased(),
            taille: (env["MURMURE_MODEL_SIZE"] ?? (connu ? conf["MODEL_SIZE"] : nil)).flatMap { Int64($0) })
    }
}

// Un téléchargement HTTP vers un fichier « .part », repris là où il s'était
// arrêté (en-tête Range, comme curl -C -). progression et fin sont appelés
// sur le fil principal.
final class Telechargement: NSObject, URLSessionDataDelegate {
    enum Fin { case termine, annule, echec(String) }

    var progression: ((Int64, Int64?) -> Void)?
    var fin: ((Fin) -> Void)?
    private let url: URL
    private let part: String
    private let taille: Int64?
    private var session: URLSession?
    private var fichier: FileHandle?
    private var recus: Int64 = 0
    private var total: Int64?
    private var probleme: String?   // refus du serveur ou écriture impossible
    private var signale = Date.distantPast

    init(url: URL, vers part: String, taille: Int64?) {
        self.url = url
        self.part = part
        self.taille = taille
    }

    func demarrer() {
        var deja = Modele.taille(part)
        if let taille, deja >= taille {
            // Déjà complet : une plage vide serait refusée par le serveur.
            if deja == taille { DispatchQueue.main.async { self.conclure(.termine) }; return }
            try? FileManager.default.removeItem(atPath: part)
            deja = 0
        }
        if !FileManager.default.fileExists(atPath: part) { FileManager.default.createFile(atPath: part, contents: nil) }
        guard let f = FileHandle(forWritingAtPath: part) else {
            DispatchQueue.main.async { self.conclure(.echec("écriture impossible dans \(self.part)")) }
            return
        }
        fichier = f
        recus = deja
        var requete = URLRequest(url: url)
        if deja > 0 { requete.setValue("bytes=\(deja)-", forHTTPHeaderField: "Range") }
        requete.setValue("Murmure/\(versionMurmure)", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30   // 30 s sans recevoir un octet : coupure
        let file = OperationQueue()
        file.maxConcurrentOperationCount = 1
        let s = URLSession(configuration: config, delegate: self, delegateQueue: file)
        session = s
        s.dataTask(with: requete).resume()
    }

    func annuler() { session?.invalidateAndCancel() }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let plage = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range") ?? ""
        // « bytes début-fin/total »
        let nombres = plage.split(whereSeparator: { !$0.isNumber }).compactMap { Int64($0) }
        switch code {
        case 206 where nombres.first == recus:
            total = nombres.count >= 3 ? nombres[2] : taille
        case 200:
            // Reprise ignorée par le serveur : le fichier entier repart de zéro.
            if recus > 0 { try? fichier?.truncate(atOffset: 0) }
            recus = 0
            total = response.expectedContentLength > 0 ? response.expectedContentLength : taille
        case 206, 416:
            // Plage refusée ou décalée : le prochain essai repartira de zéro.
            try? fichier?.truncate(atOffset: 0)
            probleme = "reprise refusée par le serveur, le prochain essai repartira de zéro"
        default:
            probleme = "le serveur a répondu « HTTP \(code) »"
        }
        if probleme == nil, let taille, let total, total != taille {
            probleme = "le fichier proposé ne fait pas la taille attendue (\(total) octets au lieu de \(taille))"
        }
        if probleme != nil { completionHandler(.cancel); return }
        _ = try? fichier?.seekToEnd()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fichier?.write(contentsOf: data)
        } catch {
            let n = error as NSError
            let plein = n.code == NSFileWriteOutOfSpaceError || (n.domain == NSPOSIXErrorDomain && n.code == Int(ENOSPC))
            probleme = plein ? "disque plein" : "écriture impossible (\(error.localizedDescription))"
            dataTask.cancel()
            return
        }
        recus += Int64(data.count)
        let maintenant = Date()
        if maintenant.timeIntervalSince(signale) >= 0.2 {
            signale = maintenant
            let (r, t) = (recus, total)
            DispatchQueue.main.async { self.progression?(r, t) }
        }
    }

    // Hugging Face redirige vers son CDN : la plage demandée doit suivre.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var r = request
        if let plage = task.originalRequest?.value(forHTTPHeaderField: "Range") {
            r.setValue(plage, forHTTPHeaderField: "Range")
        }
        completionHandler(r)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fichier?.close()
        fichier = nil
        session.finishTasksAndInvalidate()
        let issue: Fin
        if let probleme {
            issue = .echec(probleme)
        } else if let error {
            issue = (error as? URLError)?.code == .cancelled ? .annule : .echec(Telechargement.decrire(error))
        } else if let attendu = taille ?? total, recus != attendu {
            issue = .echec("téléchargement incomplet (\(recus) octets sur \(attendu))")
        } else {
            issue = .termine
        }
        DispatchQueue.main.async { self.conclure(issue) }
    }

    private func conclure(_ issue: Fin) {
        let f = fin
        fin = nil
        progression = nil
        f?(issue)
    }

    static func decrire(_ erreur: Error) -> String {
        switch (erreur as? URLError)?.code {
        case .notConnectedToInternet?: return "pas de connexion à Internet"
        case .networkConnectionLost?: return "connexion perdue"
        case .timedOut?: return "le serveur ne répond plus"
        case .cannotFindHost?, .cannotConnectToHost?, .dnsLookupFailed?: return "serveur injoignable"
        default: return erreur.localizedDescription
        }
    }
}
