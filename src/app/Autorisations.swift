import AppKit
import ApplicationServices
import AVFoundation

// Autorisations dont dépend Murmure. osascript et ffmpeg, lancés par
// murmure.sh, sont des processus enfants de l'app : macOS leur applique les
// autorisations de Murmure.app, que l'app peut donc vérifier elle-même.
// - Accessibilité (⌘V automatique) : AXIsProcessTrusted(), sans invite.
//   Quand Murmure.app est recréée, l'ancienne entrée des Réglages reste
//   cochée mais ne vaut plus : il faut la supprimer (–) puis la rajouter.
// - Micro : seul un refus explicite est signalé ; non déterminé, macOS pose
//   la question à la première dictée.
// Tant qu'il manque quelque chose : une ligne d'alerte en tête du menu, une
// icône marquée, et une vérification toutes les 2 s, arrêtée dès que tout
// est accordé. Une alerte explicative s'affiche une seule fois par version
// de l'app (mémoire : $MURMURE_HOME/.autorisations).
//
// MURMURE_AX_NO_PROMPT=1 (environnement, tests) : ni invite système, ni
// alerte, ni ouverture des Réglages ; le journal note ce qui aurait eu lieu.
final class Autorisations: NSObject {
    private static let reglagesAccessibilite = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    private static let reglagesMicro = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

    let accessibilite = NSMenuItem(title: "⚠︎ Collage automatique désactivé — Autoriser…", action: #selector(autoriserAccessibilite), keyEquivalent: "")
    let micro = NSMenuItem(title: "⚠︎ Micro refusé — Autoriser…", action: #selector(autoriserMicro), keyEquivalent: "")
    let relancer = NSMenuItem(title: "Relancer Murmure", action: #selector(relancerMurmure), keyEquivalent: "")
    let separateur = NSMenuItem.separator()
    // Appelé quand l'état change : la barre redessine son icône.
    var changement: (() -> Void)?

    private let memoire = murmureHome + "/.autorisations"
    private let sansInvite = ProcessInfo.processInfo.environment["MURMURE_AX_NO_PROMPT"] == "1"
    private let lancement = Date()
    private var reglagesOuverts = false   // l'utilisateur est allé dans les Réglages
    private var minuterie: Timer?
    private(set) var manque = false

    override init() {
        super.init()
        for i in [accessibilite, micro, relancer] { i.target = self }
        for i in [accessibilite, micro, relancer, separateur] { i.isHidden = true }
    }

    private var accessibiliteAccordee: Bool { AXIsProcessTrusted() }
    private var microRefuse: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        return s == .denied || s == .restricted
    }

    // murmure.sh dépose ce fichier quand macOS refuse le ⌘V (erreur 1002) :
    // si l'app se croit pourtant autorisée, seule une relance le règle.
    private var collageRefuse: Bool {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: stateDir + "/collage-refuse"),
              let date = attr[.modificationDate] as? Date else { return false }
        return date > lancement
    }

    func demarrer() {
        verifier()
        let ax = accessibiliteAccordee, mic = !microRefuse
        journal("autorisations : Accessibilité \(ax ? "accordée" : "absente"), Micro \(mic ? "non refusé" : "refusé")")
        if ax && mic {
            try? FileManager.default.removeItem(atPath: memoire)   // alerte à revoir si elle se perd
        } else if lireMemoire() != empreinte {
            try? (empreinte + "\n").write(toFile: memoire, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { self.expliquer(accessibilite: !ax) }
        }
    }

    // Met le menu et l'icône à jour. Peu coûteux : appelé à l'ouverture du
    // menu, après chaque dictée et toutes les 2 s tant qu'il manque quelque chose.
    func verifier() {
        let ax = accessibiliteAccordee, micRefuse = microRefuse
        let aRelancer = (!ax && reglagesOuverts) || (ax && collageRefuse)
        accessibilite.isHidden = ax
        micro.isHidden = !micRefuse
        relancer.isHidden = !aRelancer
        relancer.title = ax ? "⚠︎ Collage refusé par macOS — Relancer Murmure" : "Relancer Murmure"
        separateur.isHidden = ax && !micRefuse && !aRelancer

        let nouveau = !ax || micRefuse || aRelancer
        if nouveau != manque {
            manque = nouveau
            journal(nouveau ? "autorisations : alerte affichée dans le menu" : "autorisations : tout est accordé")
            changement?()
        }
        if !ax || micRefuse {
            if minuterie == nil {
                minuterie = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.verifier() }
            }
        } else {
            minuterie?.invalidate(); minuterie = nil
        }
    }

    @objc private func autoriserAccessibilite() {
        if sansInvite {
            journal("autorisations : invite Accessibilité neutralisée (MURMURE_AX_NO_PROMPT)")
        } else {
            // Ajoute Murmure à la liste des Réglages (décochée) et affiche l'invite système.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        ouvrir(Autorisations.reglagesAccessibilite)
    }

    @objc private func autoriserMicro() { ouvrir(Autorisations.reglagesMicro) }

    // Une nouvelle instance est ouverte une fois celle-ci terminée (le verrou
    // d'instance unique est alors libéré). Les variables MURMURE_* suivent.
    @objc private func relancerMurmure() {
        journal("relance demandée")
        var args = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; shift; exec /usr/bin/open \"$@\"",
                    "_", String(getpid())]
        for (cle, valeur) in ProcessInfo.processInfo.environment where cle.hasPrefix("MURMURE_") {
            args += ["--env", "\(cle)=\(valeur)"]
        }
        args.append(Bundle.main.bundlePath)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = args
        do {
            try p.run()
            NSApp.terminate(nil)
        } catch {
            journal("relance impossible : \(error.localizedDescription)")
        }
    }

    private func ouvrir(_ adresse: String) {
        reglagesOuverts = true
        verifier()
        if sansInvite {
            journal("autorisations : ouverture des Réglages neutralisée (\(adresse))")
        } else if let url = URL(string: adresse) {
            NSWorkspace.shared.open(url)
        }
    }

    private func expliquer(accessibilite: Bool) {
        let a = NSAlert()
        if accessibilite {
            a.messageText = "Collage automatique désactivé"
            a.informativeText = """
                Murmure n'a pas l'autorisation Accessibilité : le texte dicté est copié, \
                mais il faut le coller soi-même (⌘V).

                Dans Réglages > Confidentialité et sécurité > Accessibilité :
                • si Murmure figure déjà dans la liste, même cochée, sélectionnez-la et \
                supprimez-la (–) : après une mise à jour, l'ancienne entrée ne vaut plus ;
                • ajoutez Murmure (+, puis ⌘⇧G et \(Bundle.main.bundlePath)) et cochez-la.

                L'alerte du menu disparaît dès que l'autorisation est accordée.
                """
        } else {
            a.messageText = "Micro refusé"
            a.informativeText = """
                Murmure n'a pas accès au micro : les dictées resteraient muettes.

                Dans Réglages > Confidentialité et sécurité > Micro, cochez Murmure.
                """
        }
        a.addButton(withTitle: "Ouvrir les réglages")
        a.addButton(withTitle: "Plus tard")
        if sansInvite {
            journal("autorisations : alerte « \(a.messageText) » neutralisée (MURMURE_AX_NO_PROMPT)")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            ouvrir(accessibilite ? Autorisations.reglagesAccessibilite : Autorisations.reglagesMicro)
        }
    }

    // Une version de l'app = une empreinte de ses sources (inscrite par install.sh).
    private var empreinte: String {
        Bundle.main.object(forInfoDictionaryKey: "MurmureSourceSum") as? String ?? versionMurmure
    }

    private func lireMemoire() -> String? {
        (try? String(contentsOfFile: memoire, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
