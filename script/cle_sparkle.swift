// Clés EdDSA de Sparkle en fichier, sans trousseau : clé jetable pour les
// essais, clé publique d'une clé en fichier, et vérification indépendante de
// la signature d'une archive (celle que fera l'app installée).
//
//   xcrun swift script/cle_sparkle.swift nouvelle <fichier>
//   xcrun swift script/cle_sparkle.swift publique <fichier>
//   xcrun swift script/cle_sparkle.swift verifier <clé publique> <signature> <archive>
//
// Format du fichier : celui de --ed-key-file (generate_appcast, sign_update)
// et de « generate_keys -x » : la graine Ed25519 en base64 (32 octets), ou
// l'ancien format de Sparkle (96 octets, clé publique à la fin).
import CryptoKit
import Foundation

func echec(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func lireCle(_ chemin: String) -> Data {
    guard let texte = try? String(contentsOfFile: chemin, encoding: .utf8),
          let octets = Data(base64Encoded: texte.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        echec("clé illisible : \(chemin)")
    }
    return octets
}

let args = Array(CommandLine.arguments.dropFirst())
switch (args.first, args.count) {
case ("nouvelle", 2):
    let cle = Curve25519.Signing.PrivateKey()
    // Créé en 0600 : même jetable, une clé privée ne doit pas être lisible
    // par les autres comptes.
    guard FileManager.default.createFile(atPath: args[1],
                                         contents: Data((cle.rawRepresentation.base64EncodedString() + "\n").utf8),
                                         attributes: [.posixPermissions: 0o600]) else {
        echec("écriture impossible : \(args[1])")
    }
    print(cle.publicKey.rawRepresentation.base64EncodedString())
case ("publique", 2):
    let octets = lireCle(args[1])
    switch octets.count {
    case 32:
        guard let cle = try? Curve25519.Signing.PrivateKey(rawRepresentation: octets) else { echec("graine invalide : \(args[1])") }
        print(cle.publicKey.rawRepresentation.base64EncodedString())
    case 96:
        print(octets.suffix(32).base64EncodedString())
    default:
        echec("format de clé inconnu (\(octets.count) octets) : \(args[1])")
    }
case ("verifier", 4):
    guard let publique = Data(base64Encoded: args[1]),
          let cle = try? Curve25519.Signing.PublicKey(rawRepresentation: publique) else { echec("clé publique invalide : \(args[1])") }
    guard let signature = Data(base64Encoded: args[2]) else { echec("signature invalide : \(args[2])") }
    guard let archive = FileManager.default.contents(atPath: args[3]) else { echec("archive illisible : \(args[3])") }
    guard cle.isValidSignature(signature, for: archive) else { echec("signature EdDSA refusée par la clé \(args[1])") }
    print("signature EdDSA valide")
default:
    echec("usage : cle_sparkle.swift nouvelle <fichier> | publique <fichier> | verifier <clé publique> <signature> <archive>")
}
