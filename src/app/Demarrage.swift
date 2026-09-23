import Foundation
import ServiceManagement

// Lancement au démarrage de session : SMAppService (élément de connexion géré
// par macOS), sinon, si l'enregistrement est refusé — la signature ad hoc ne
// convient pas toujours —, un LaunchAgent qui ouvre l'app.
// MURMURE_DEMARRAGE=launchagent force le LaunchAgent, et
// MURMURE_LAUNCH_AGENTS_DIR en change le dossier (tests).
enum Demarrage {
    static let etiquette = "dev.croustibat.murmure"

    private static var agentSeul: Bool {
        ProcessInfo.processInfo.environment["MURMURE_DEMARRAGE"] == "launchagent"
    }

    static var agent: URL {
        let dir = ProcessInfo.processInfo.environment["MURMURE_LAUNCH_AGENTS_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? NSString(string: "~/Library/LaunchAgents").expandingTildeInPath
        return URL(fileURLWithPath: dir).appendingPathComponent(etiquette + ".plist")
    }

    static var actif: Bool {
        (!agentSeul && SMAppService.mainApp.status == .enabled)
            || FileManager.default.fileExists(atPath: agent.path)
    }

    static func activer(_ oui: Bool) throws {
        if oui {
            if !agentSeul {
                do {
                    try SMAppService.mainApp.register()
                    if SMAppService.mainApp.status == .requiresApproval {
                        journal("démarrage : à approuver dans Réglages > Général > Ouverture")
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    journal("démarrage : élément de connexion enregistré")
                    return
                } catch {
                    journal("démarrage : SMAppService refusé (\(error.localizedDescription)), LaunchAgent à la place")
                }
            }
            let plist: [String: Any] = [
                "Label": etiquette,
                "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: agent, options: .atomic)
            journal("démarrage : LaunchAgent \(agent.path)")
        } else {
            if !agentSeul, SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
                journal("démarrage : élément de connexion retiré")
            }
            if FileManager.default.fileExists(atPath: agent.path) {
                try FileManager.default.removeItem(at: agent)
                journal("démarrage : LaunchAgent retiré")
            }
        }
    }

    // « Murmure --demarrage oui|non|etat », utilisé par uninstall.sh.
    static func ligneDeCommande(_ args: [String]) -> Int32 {
        do {
            switch args.first {
            case "oui": try activer(true)
            case "non": try activer(false)
            case "etat": break
            default:
                FileHandle.standardError.write(Data("usage : Murmure --demarrage oui|non|etat\n".utf8))
                return 2
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
        print(actif ? "actif" : "inactif")
        return 0
    }
}
