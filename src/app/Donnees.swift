import Foundation

// $MURMURE_HOME ne contient que les données de l'utilisateur : réglages,
// vocabulaire, corrections, modèle, historique. Le moteur et les réglages par
// défaut voyagent dans le bundle (Contents/Resources/defaults) ; au lancement,
// l'app dépose ceux qui manquent, sans jamais écraser un fichier existant.
// Un vocabulaire ou des corrections modifiés par l'utilisateur sont gardés, et
// la version par défaut de l'app va à côté, en .dist, comme le fait install.sh.
enum Donnees {
    // Fichier de $MURMURE_HOME, son modèle dans le bundle, et s'il reçoit un
    // .dist : config n'en a pas, toutes ses clés y figurent déjà en commentaire.
    private static let fichiers: [(nom: String, modele: String, dist: Bool)] = [
        ("config", "config.exemple", false),
        ("vocabulaire.txt", "vocabulaire.txt", true),
        ("corrections.txt", "corrections.txt", true),
    ]

    static func preparer() {
        do {
            try FileManager.default.createDirectory(atPath: murmureHome, withIntermediateDirectories: true)
        } catch {
            journal("création de \(murmureHome) impossible : \(error.localizedDescription)")
            return
        }
        guard let defauts = Bundle.main.resourceURL?.appendingPathComponent("defaults") else { return }
        let home = URL(fileURLWithPath: murmureHome)
        for f in fichiers {
            guard let modele = try? Data(contentsOf: defauts.appendingPathComponent(f.modele)) else {
                journal("réglage par défaut absent du bundle : \(f.modele)")
                continue
            }
            let cible = home.appendingPathComponent(f.nom)
            if let actuel = try? Data(contentsOf: cible) {
                guard f.dist, actuel != modele else { continue }
                // Réécrit seulement quand la version par défaut change.
                let dist = cible.appendingPathExtension("dist")
                if (try? Data(contentsOf: dist)) != modele {
                    do {
                        try modele.write(to: dist, options: .atomic)
                        journal("\(f.nom) conservé, version par défaut dans \(f.nom).dist")
                    } catch {
                        journal("\(f.nom).dist : écriture impossible (\(error.localizedDescription))")
                    }
                }
            } else {
                // .withoutOverwriting : un fichier apparu entre-temps, ou
                // illisible, n'est jamais remplacé.
                do {
                    try modele.write(to: cible, options: .withoutOverwriting)
                    journal("\(f.nom) déposé dans \(murmureHome)")
                } catch {
                    journal("\(f.nom) : dépôt impossible (\(error.localizedDescription))")
                }
            }
        }
    }
}
