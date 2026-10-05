import AppKit
import Sparkle

// Mises à jour par Sparkle. Flux (appcast.xml de la dernière GitHub Release),
// clé publique EdDSA et vérification quotidienne sont déclarés dans
// Info.plist ; Sparkle télécharge l'archive, vérifie sa signature, remplace
// l'app et la relance.
//
// Créé par la barre, donc seulement dans l'instance résidente : les
// lancements en mode commande (press, release…, --demarrage,
// --presse-papiers) s'arrêtent avant et ne démarrent jamais Sparkle.
//
// MURMURE_CHECK_UPDATES=0 (environnement ou config, lu au lancement) :
// Sparkle n'est pas démarré, aucune requête n'est faite et l'entrée
// « Rechercher les mises à jour… » est masquée.
//
// Une mise à jour n'interrompt pas une dictée. Pendant une capture ou une
// transcription, la relance qui installe est différée jusqu'au retour à
// « Prêt », et une version trouvée par la vérification quotidienne n'ouvre
// pas de fenêtre (elle prendrait le premier plan à l'app où coller) : une
// entrée du menu la signale.
final class MisesAJourSparkle: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    let disponible = NSMenuItem(title: "", action: #selector(rechercherMaintenant), keyEquivalent: "")
    let rechercher = NSMenuItem(title: "Rechercher les mises à jour…", action: #selector(rechercherMaintenant), keyEquivalent: "")
    private let dicteeEnCours: () -> Bool
    private let actif = reglage("MURMURE_CHECK_UPDATES") != "0"
    private var controleur: SPUStandardUpdaterController?
    private var relanceDifferee: (() -> Void)?

    // dicteeEnCours : vrai pendant une capture ou une transcription (état
    // tenu par la barre).
    init(dicteeEnCours: @escaping () -> Bool) {
        self.dicteeEnCours = dicteeEnCours
        super.init()
        disponible.target = self
        rechercher.target = self
        disponible.isHidden = true
        rechercher.isHidden = !actif
    }

    func demarrer() {
        // Mémoire de la vérification maison des versions ≤ 1.1.0.
        try? FileManager.default.removeItem(atPath: murmureHome + "/.mises-a-jour")
        guard actif else { journal("vérification des mises à jour désactivée"); return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        controleur = c
        journal("mises à jour : Sparkle actif (\(c.updater.feedURL?.absoluteString ?? "flux absent"))")
    }

    // Appelé par la barre à chaque retour à « Prêt ».
    func dicteeTerminee() {
        guard let relance = relanceDifferee else { return }
        relanceDifferee = nil
        journal("mises à jour : dictée terminée, installation et relance")
        relance()
    }

    @objc private func rechercherMaintenant() { controleur?.checkForUpdates(nil) }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard dicteeEnCours() else { return false }
        journal("mises à jour : \(item.displayVersionString) prête, installée à la fin de la dictée")
        relanceDifferee = installHandler
        return true
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        journal("mises à jour : version \(item.displayVersionString) (\(item.versionString)) disponible")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        journal("mises à jour : \(versionMurmure) est à jour")
    }

    // Hors ligne ou erreur : une ligne de journal ; Sparkle n'affiche rien
    // pour une vérification quotidienne.
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let e = error as NSError
        guard !(e.domain == SUSparkleErrorDomain && e.code == Int(SUError.noUpdateError.rawValue)) else { return }
        journal("mises à jour : \(e.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        journal("mises à jour : installation de \(item.displayVersionString)")
    }

    // MARK: SPUStandardUserDriverDelegate

    // App sans Dock : Sparkle demande qu'on déclare gérer ses rappels.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        !dicteeEnCours()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if handleShowingUpdate {
            // Sinon l'alerte s'ouvre derrière l'app au premier plan.
            NSApp.activate(ignoringOtherApps: true)
        } else {
            journal("mises à jour : dictée en cours, \(update.displayVersionString) signalée dans le menu")
            disponible.title = "Version \(update.displayVersionString) disponible…"
            disponible.isHidden = false
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { disponible.isHidden = true }

    func standardUserDriverWillFinishUpdateSession() { disponible.isHidden = true }
}
