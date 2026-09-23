import AppKit

// Murmure — app résidente dans la barre des menus.
// Elle enregistre le raccourci global et pilote murmure.sh, qui fait tout le
// travail (capture, transcription, collage). Aucun modèle n'est gardé en
// mémoire : Whisper est chargé à chaque dictée, comme avant.
//
// Lancée avec une sous-commande (toggle, press, release, cancel), elle
// l'exécute et s'arrête sans interface : les outils tiers (Raycast,
// Karabiner…) qui appellent « open -n -a Murmure.app --args press » marchent
// toujours.

let commandes: Set<String> = ["toggle", "press", "release", "cancel"]

// Dossier d'installation : variable d'environnement, sinon celui inscrit par
// install.sh dans Info.plist, sinon l'emplacement par défaut.
let murmureHome: String = {
    if let h = ProcessInfo.processInfo.environment["MURMURE_HOME"], !h.isEmpty { return h }
    if let h = Bundle.main.object(forInfoDictionaryKey: "MurmureHome") as? String, !h.isEmpty { return h }
    return NSString(string: "~/.local/share/murmure").expandingTildeInPath
}()
let script = murmureHome + "/murmure.sh"
let stateDir = ProcessInfo.processInfo.environment["MURMURE_STATE_DIR"].flatMap { $0.isEmpty ? nil : $0 }
    ?? "/tmp/murmure-\(getuid())"
let statusPath = stateDir + "/status"
let logPath = stateDir + "/murmure.log"
let versionMurmure = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

// Même format que le journal de murmure.sh.
func journal(_ message: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    let line = "[\(f.string(from: Date()))] app : \(message)\n"
    if let fh = FileHandle(forWritingAtPath: logPath) {
        fh.seekToEndOfFile()
        fh.write(Data(line.utf8))
        fh.closeFile()
    } else {
        try? line.write(toFile: logPath, atomically: false, encoding: .utf8)
    }
}

// Lecture minimale de $MURMURE_HOME/config (lignes CLE=valeur, # pour
// commenter, guillemets retirés) : l'environnement l'emporte sur le fichier.
func reglage(_ cle: String) -> String? {
    if let v = ProcessInfo.processInfo.environment[cle], !v.isEmpty { return v }
    guard let texte = try? String(contentsOfFile: murmureHome + "/config", encoding: .utf8) else { return nil }
    var trouve: String?
    for ligne in texte.split(separator: "\n") {
        let l = ligne.trimmingCharacters(in: .whitespaces)
        guard !l.hasPrefix("#"), let eq = l.firstIndex(of: "="),
              l[..<eq].trimmingCharacters(in: .whitespaces) == cle else { continue }
        var v = l[l.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if v.count >= 2, let q = v.first, q == "\"" || q == "'", v.last == q {
            v = String(v.dropFirst().dropLast())
        }
        trouve = v
    }
    return trouve.flatMap { $0.isEmpty ? nil : $0 }
}

// Lance murmure.sh sans attendre : press, release et cancel tournent en
// parallèle, le script arbitre (comme avec les « open -n » de Karabiner).
func lancer(_ commande: String, fin: (() -> Void)? = nil) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: script)
    p.arguments = [commande]
    var env = ProcessInfo.processInfo.environment
    env["MURMURE_HOME"] = murmureHome
    p.environment = env
    p.terminationHandler = { _ in DispatchQueue.main.async { fin?() } }
    do { try p.run() } catch { journal("lancement de \(script) impossible : \(error.localizedDescription)") }
}

@main
enum Principal {
    static func main() {
        // Au lancement par LaunchServices, macOS peut ajouter « -psn_… ».
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        if let cmd = args.first, commandes.contains(cmd) {
            // Mode compatibilité : le script remplace ce processus, qui reste
            // le processus responsable aux yeux de macOS (Micro, Accessibilité).
            setenv("MURMURE_HOME", murmureHome, 1)
            let argv: [UnsafeMutablePointer<CChar>?] = [strdup(script), strdup(cmd), nil]
            execv(script, argv)
            journal("exécution de \(script) impossible : \(String(cString: strerror(errno)))")
            exit(1)
        }
        if args.first == "--demarrage" {
            exit(Demarrage.ligneDeCommande(Array(args.dropFirst())))
        }
        if let a = args.first {
            journal("argument inconnu : \(a)")
            exit(2)
        }

        // Instance unique : le verrou est libéré par le système à la sortie,
        // même en cas de plantage.
        let fd = open(stateDir + "/app.lock", O_CREAT | O_RDWR, 0o600)
        if fd < 0 || flock(fd, LOCK_EX | LOCK_NB) != 0 {
            journal("déjà lancée : cette instance s'arrête")
            exit(0)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let barre = Barre()
        app.delegate = barre
        app.run()
    }
}
