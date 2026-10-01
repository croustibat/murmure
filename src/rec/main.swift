import AudioToolbox
import AVFAudio
import CoreAudio
import Foundation

// Murmure — enregistreur du micro, à la place de ffmpeg.
//
//   murmure-rec --device <nom|:index|:default> [--max <secondes>] [--levels <fichier>] <sortie.wav>
//   murmure-rec --list-devices      noms des micros, dans l'ordre des index « :N »
//   murmure-rec --peak <fichier.wav>   pic sonore en dB (comme volumedetect)
//
// Sortie WAV PCM 16 bits, 16 kHz, mono, lisible par whisper-cli. Toutes les
// 50 ms, le niveau RMS de la voix est ajouté à --levels au format qu'écrivait
// ffmpeg (ametadata, clé lavfi.astats.Overall.RMS_level, en dBFS) : la pastille
// le lit tel quel. Le fichier n'est créé qu'une fois le micro en marche, ce qui
// sert de signal « prêt » à murmure.sh.
// SIGINT ou SIGTERM finalise le WAV et quitte (code 0), comme --max atteint.
//
// Capture par l'AUHAL de Core Audio plutôt qu'AVAudioEngine ou
// AVCaptureSession : mesuré du lancement au premier échantillon, ~0,3 s contre
// ~0,5 s (AVCaptureSession), ~0,8 s (AVAudioEngine) et ~0,6 s pour ffmpeg.
// Le micro est celui de l'app qui lance murmure.sh : c'est elle, processus
// responsable, qui porte l'autorisation Micro.

let frequenceSortie = 16000.0
let tramesNiveau = 800   // 50 ms à 16 kHz, comme asetnsamples=n=800 d'ffmpeg
let traitement = DispatchQueue(label: "murmure-rec")   // tout l'état vit ici

// Même format que le journal de murmure.sh, sur la sortie d'erreur (redirigée
// vers murmure.log).
func journal(_ message: String) {
    var t = time(nil), heure = tm()
    localtime_r(&t, &heure)
    let ligne = String(format: "[%02d:%02d:%02d] rec : ", heure.tm_hour, heure.tm_min, heure.tm_sec) + message + "\n"
    FileHandle.standardError.write(Data(ligne.utf8))
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
        usage : murmure-rec --device <nom|:index|:default> [--max <secondes>] [--levels <fichier>] <sortie.wav>
                murmure-rec --list-devices
                murmure-rec --peak <fichier.wav>

        """.utf8))
    exit(2)
}

// MARK: micros

let systeme = AudioObjectID(kAudioObjectSystemObject)

func adresse(_ selecteur: AudioObjectPropertySelector,
             _ portee: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selecteur, mScope: portee, mElement: kAudioObjectPropertyElementMain)
}

func lire<T>(_ objet: AudioObjectID, _ selecteur: AudioObjectPropertySelector, _ initiale: T) -> T? {
    var a = adresse(selecteur)
    var valeur = initiale
    var taille = UInt32(MemoryLayout<T>.size)
    let statut = withUnsafeMutableBytes(of: &valeur) {
        AudioObjectGetPropertyData(objet, &a, 0, nil, &taille, $0.baseAddress!)
    }
    return statut == noErr ? valeur : nil
}

func nom(_ id: AudioObjectID) -> String? {
    var a = adresse(kAudioObjectPropertyName)
    var valeur: Unmanaged<CFString>?
    var taille = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &taille, &valeur) == noErr else { return nil }
    return valeur?.takeRetainedValue() as String?
}

struct Micro {
    let id: AudioObjectID
    let nom: String
}

// Entrées audio visibles, dans l'ordre de Core Audio : celui des index « :N »,
// le même que la liste d'ffmpeg. Les noms sont ceux qu'affichent les Réglages
// de Murmure (AVCaptureDevice), sans le coût d'AVFoundation au démarrage.
func micros() -> [Micro] {
    var a = adresse(kAudioHardwarePropertyDevices)
    var taille: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(systeme, &a, 0, nil, &taille) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(taille) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(systeme, &a, 0, nil, &taille, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        var flux = adresse(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var n: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &flux, 0, nil, &n) == noErr, n > 0,
              lire(id, kAudioDevicePropertyIsHidden, UInt32(0)) != 1 else { return nil }
        return Micro(id: id, nom: nom(id) ?? "Micro \(id)")
    }
}

// « :default » : micro par défaut du système ; « :N » : N-ième entrée. Sinon
// un nom (« : » initial toléré) : exact, casse ignorée, puis premier micro dont
// le nom le contient, sinon micro par défaut, avec une ligne au journal.
func resoudre(_ demande: String) -> Micro? {
    let liste = micros()
    func parDefaut() -> Micro? {
        guard let id = lire(systeme, kAudioHardwarePropertyDefaultInputDevice, AudioObjectID(0)),
              id != kAudioObjectUnknown else { return nil }
        return liste.first { $0.id == id } ?? Micro(id: id, nom: nom(id) ?? "Micro \(id)")
    }
    if demande == ":default" { return parDefaut() }
    if demande.hasPrefix(":"), let i = Int(demande.dropFirst()) {
        if liste.indices.contains(i) { return liste[i] }
        journal("micro \(demande) absent : micro par défaut")
        return parDefaut()
    }
    let voulu = demande.hasPrefix(":") ? String(demande.dropFirst()) : demande
    let cle = voulu.lowercased()
    if let m = liste.first(where: { $0.nom.lowercased() == cle })
        ?? liste.first(where: { $0.nom.lowercased().contains(cle) }) {
        journal("micro « \(voulu) » : \(m.nom)")
        return m
    }
    journal("micro « \(voulu) » introuvable : micro par défaut")
    return parDefaut()
}

// MARK: capture

// Une capture AUHAL sur un micro, recréée quand il disparaît ou change de
// fréquence (casque débranché, Bluetooth qui bascule en 16 ou 24 kHz…).
final class Capture {
    let micro: Micro
    let frequence: Double
    private let unite: AudioUnit
    private let canaux: Int
    private let capacite = 16384   // trames par canal, au-delà de tout tampon matériel courant
    private let tampons: UnsafeMutableAudioBufferListPointer
    private var erreurs = 0   // rendus ratés d'affilée, sur le fil audio seulement

    init?(_ micro: Micro) {
        self.micro = micro
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        var u: AudioUnit?
        guard let composant = AudioComponentFindNext(nil, &desc),
              AudioComponentInstanceNew(composant, &u) == noErr, let u else { return nil }
        unite = u
        let entier = UInt32(MemoryLayout<UInt32>.size)
        let tailleFormat = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        // Entrée seule : sans quoi l'AUHAL ouvrirait aussi la sortie par défaut.
        var oui: UInt32 = 1, non: UInt32 = 0, id = micro.id
        var materiel = AudioStreamBasicDescription()
        var taille = tailleFormat
        guard AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &oui, entier) == noErr,
              AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &non, entier) == noErr,
              AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, entier) == noErr,
              AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &materiel, &taille) == noErr,
              materiel.mSampleRate > 0, materiel.mChannelsPerFrame > 0 else {
            AudioComponentInstanceDispose(u)
            return nil
        }
        // L'AUHAL ne rééchantillonne pas en entrée : on garde la fréquence du
        // micro, en flottants non entrelacés ; AVAudioConverter fait le reste.
        frequence = materiel.mSampleRate
        canaux = Int(materiel.mChannelsPerFrame)
        var client = AudioStreamBasicDescription(
            mSampleRate: frequence, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: materiel.mChannelsPerFrame, mBitsPerChannel: 32, mReserved: 0)
        tampons = AudioBufferList.allocate(maximumBuffers: canaux)
        for i in 0..<canaux {
            tampons[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(capacite * 4),
                                     mData: UnsafeMutableRawPointer.allocate(byteCount: capacite * 4, alignment: 16))
        }
        var rappel = AURenderCallbackStruct(inputProc: { refCon, drapeaux, horodatage, bus, trames, _ in
            Unmanaged<Capture>.fromOpaque(refCon).takeUnretainedValue()
                .recevoir(drapeaux, horodatage, bus, trames)
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        guard AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client, tailleFormat) == noErr,
              AudioUnitSetProperty(u, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                   &rappel, UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr,
              AudioUnitInitialize(u) == noErr else {
            liberer()
            return nil
        }
    }

    func demarrer() -> Bool { AudioOutputUnitStart(unite) == noErr }

    // Après AudioOutputUnitStop, plus aucun rappel n'arrive.
    func arreter() {
        AudioOutputUnitStop(unite)
        AudioUnitUninitialize(unite)
        liberer()
    }

    private func liberer() {
        AudioComponentInstanceDispose(unite)
        for b in tampons { b.mData?.deallocate() }
        tampons.unsafeMutablePointer.deallocate()
    }

    // Fil temps réel de Core Audio : lecture, mélange en mono (moyenne des
    // canaux, comme -ac 1), puis tout le reste sur la file de traitement.
    private func recevoir(_ drapeaux: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                          _ horodatage: UnsafePointer<AudioTimeStamp>,
                          _ bus: UInt32, _ trames: UInt32) -> OSStatus {
        let n = Int(trames)
        guard n <= capacite else { return kAudio_ParamError }
        for i in 0..<canaux { tampons[i].mDataByteSize = UInt32(n * 4) }
        let statut = AudioUnitRender(unite, drapeaux, horodatage, bus, trames, tampons.unsafeMutablePointer)
        guard statut == noErr else {
            // Format changé sous nos pieds : après ~0,1 s d'échecs, on repart
            // sur une capture neuve (une seule demande).
            erreurs += 1
            if erreurs == 10 {
                traitement.async { enregistreur.relancer(self, "erreur de capture \(statut)") }
            }
            return statut
        }
        erreurs = 0
        var mono = [Float](repeating: 0, count: n)
        for b in tampons {
            let p = b.mData!.assumingMemoryBound(to: Float.self)
            for i in 0..<n { mono[i] += p[i] }
        }
        if canaux > 1 {
            let k = 1 / Float(canaux)
            for i in 0..<n { mono[i] *= k }
        }
        let f = frequence
        traitement.async { enregistreur.ecrire(mono, frequence: f) }
        return noErr
    }
}

// MARK: enregistrement

final class Enregistreur {
    private let demande: String
    private let chemin: String
    private let cheminNiveaux: String?
    private let limite: Int   // échantillons à 16 kHz, 0 : sans limite
    private let formatSortie = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: frequenceSortie,
                                             channels: 1, interleaved: true)!
    private var capture: Capture?
    private var convertisseur: AVAudioConverter?
    private var wav: Int32 = -1
    private var niveaux: Int32 = -1
    private var ecrits = 0
    private var trame = 0, cumul = 0.0, dansTrame = 0
    private var arretDemande = false
    private var fini = false
    private var erreurEcriture = false

    init(demande: String, chemin: String, niveaux: String?, max: Double) {
        self.demande = demande
        self.chemin = chemin
        cheminNiveaux = niveaux
        limite = max > 0 ? Int(max * frequenceSortie) : 0
    }

    // Sur la file de traitement. Sans capture, pas de WAV : murmure.sh dira
    // « Aucun fichier audio produit » plutôt que « Trop court ».
    func demarrer() {
        guard let micro = resoudre(demande) else {
            journal("aucun micro disponible")
            exit(1)
        }
        wav = open(chemin, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard wav >= 0, ecrireEntete() else {
            journal("\(chemin) : \(String(cString: strerror(errno)))")
            exit(1)
        }
        guard let c = ouvrir(micro) else {
            unlink(chemin)
            exit(1)
        }
        capture = c
        surveiller(c)
    }

    private func ouvrir(_ micro: Micro) -> Capture? {
        guard let c = Capture(micro) else {
            journal("ouverture de « \(micro.nom) » impossible")
            return nil
        }
        guard c.demarrer() else {
            journal("démarrage de « \(micro.nom) » impossible")
            c.arreter()
            return nil
        }
        return c
    }

    // Micro débranché ou changé de fréquence : la capture reprend sur le micro
    // demandé s'il est encore là, sinon sur celui par défaut. Les écouteurs ne
    // visent que leur capture : ceux d'une capture remplacée sont sans effet,
    // d'où leur absence de retrait.
    private func surveiller(_ c: Capture) {
        var vivant = adresse(kAudioDevicePropertyDeviceIsAlive)
        AudioObjectAddPropertyListenerBlock(c.micro.id, &vivant, traitement) { [weak self] _, _ in
            if lire(c.micro.id, kAudioDevicePropertyDeviceIsAlive, UInt32(1)) != 1 {
                self?.relancer(c, "micro « \(c.micro.nom) » débranché")
            }
        }
        var frequence = adresse(kAudioDevicePropertyNominalSampleRate)
        AudioObjectAddPropertyListenerBlock(c.micro.id, &frequence, traitement) { [weak self] _, _ in
            if lire(c.micro.id, kAudioDevicePropertyNominalSampleRate, Float64(0)) != c.frequence {
                self?.relancer(c, "fréquence de « \(c.micro.nom) » changée")
            }
        }
    }

    func relancer(_ ancienne: Capture, _ raison: String) {
        guard !arretDemande, capture === ancienne else { return }
        ancienne.arreter()
        capture = nil
        guard let micro = resoudre(demande), let c = ouvrir(micro) else {
            journal("\(raison) : plus de micro, capture terminée")
            arreter()
            return
        }
        journal("\(raison) : capture reprise sur « \(micro.nom) »")
        capture = c
        surveiller(c)
    }

    func ecrire(_ mono: [Float], frequence: Double) {
        guard !fini, !mono.isEmpty else { return }
        if convertisseur?.inputFormat.sampleRate != frequence {
            if convertisseur != nil { convertir(nil) }   // reliquat de l'ancien micro
            let entree = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: frequence,
                                       channels: 1, interleaved: false)!
            convertisseur = AVAudioConverter(from: entree, to: formatSortie)
            convertisseur?.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        }
        guard let conv = convertisseur,
              let tampon = AVAudioPCMBuffer(pcmFormat: conv.inputFormat, frameCapacity: AVAudioFrameCount(mono.count)) else { return }
        mono.withUnsafeBufferPointer { tampon.floatChannelData![0].update(from: $0.baseAddress!, count: mono.count) }
        tampon.frameLength = AVAudioFrameCount(mono.count)
        convertir(tampon)
    }

    // nil : fin du flux, le convertisseur rend ce qu'il retenait encore.
    private func convertir(_ entree: AVAudioPCMBuffer?) {
        guard let conv = convertisseur else { return }
        var aFournir = entree
        while let sortie = AVAudioPCMBuffer(pcmFormat: formatSortie, frameCapacity: 4096) {
            var erreur: NSError?
            let statut = conv.convert(to: sortie, error: &erreur) { _, etat in
                if let e = aFournir {
                    aFournir = nil
                    etat.pointee = .haveData
                    return e
                }
                etat.pointee = entree == nil ? .endOfStream : .noDataNow
                return nil
            }
            ajouter(sortie)
            if statut != .haveData {
                if let erreur { journal("conversion : \(erreur.localizedDescription)") }
                break
            }
        }
        if entree == nil { conv.reset() }
    }

    private func ajouter(_ sortie: AVAudioPCMBuffer) {
        var n = Int(sortie.frameLength)
        if limite > 0 { n = min(n, limite - ecrits) }
        guard n > 0, let p = sortie.int16ChannelData?[0] else { return }
        // Premier son : le fichier de niveaux annonce que la capture tourne.
        if niveaux < 0, let c = cheminNiveaux {
            niveaux = open(c, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        }
        // Écritures positionnées : l'en-tête, réécrit en place, ne déplace rien.
        if pwrite(wav, p, n * 2, off_t(44 + ecrits * 2)) != n * 2, !erreurEcriture {
            erreurEcriture = true
            journal("\(chemin) : \(String(cString: strerror(errno)))")
        }
        ecrits += n
        // Tailles mises à jour à chaque ajout : même tué net, le WAV reste lisible.
        _ = ecrireEntete()
        for i in 0..<n { niveau(p[i]) }
        if limite > 0, ecrits >= limite { arreter() }
    }

    // Une ligne de niveau par trame de 800 échantillons, au format exact de
    // « ametadata=print » d'ffmpeg (RMS en dBFS, « -inf » pour le silence).
    private func niveau(_ s: Int16) {
        let x = Double(s) / 32768
        cumul += x * x
        dansTrame += 1
        guard dansTrame == tramesNiveau else { return }
        let rms = (cumul / Double(tramesNiveau)).squareRoot()
        let pts = trame * tramesNiveau
        let ligne = String(format: "frame:%-4ld pts:%-7ld pts_time:%.6g\nlavfi.astats.Overall.RMS_level=%f\n",
                           trame, pts, Double(pts) / frequenceSortie, 20 * log10(rms))
        if niveaux >= 0 { _ = ligne.withCString { write(niveaux, $0, strlen($0)) } }
        trame += 1
        cumul = 0
        dansTrame = 0
    }

    // En-tête WAV de 44 octets ; les tailles RIFF et data suivent ecrits.
    private func ecrireEntete() -> Bool {
        let donnees = UInt32(ecrits * 2)
        var e = Data()
        func mot32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { e.append(contentsOf: $0) } }
        func mot16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { e.append(contentsOf: $0) } }
        e.append(contentsOf: Array("RIFF".utf8)); mot32(36 + donnees)
        e.append(contentsOf: Array("WAVEfmt ".utf8)); mot32(16)
        mot16(1); mot16(1)                                   // PCM, mono
        mot32(UInt32(frequenceSortie)); mot32(UInt32(frequenceSortie) * 2)
        mot16(2); mot16(16)                                  // 2 octets par trame, 16 bits
        e.append(contentsOf: Array("data".utf8)); mot32(donnees)
        return e.withUnsafeBytes { pwrite(wav, $0.baseAddress, 44, 0) } == 44
    }

    // Fin : SIGINT, SIGTERM, --max atteint ou plus de micro. Les tampons déjà
    // en file passent avant la finalisation.
    func arreter() {
        guard !arretDemande else { return }
        arretDemande = true
        capture?.arreter()
        capture = nil
        traitement.async { [self] in
            convertir(nil)
            fini = true
            _ = ecrireEntete()
            close(wav)
            if niveaux >= 0 { close(niveaux) }
            exit(0)
        }
    }
}

// MARK: pic sonore

// Pic du WAV en dB pleine échelle, une décimale, -91.0 pour un silence total :
// la valeur « max_volume » de volumedetect, pour la garde anti-silence.
func pic(_ chemin: String) -> Never {
    guard let d = FileManager.default.contents(atPath: chemin), d.count >= 12,
          d.prefix(4) == Data("RIFF".utf8) else {
        journal("\(chemin) : WAV illisible")
        exit(1)
    }
    // Recherche du bloc « data » : ffmpeg ajoute un bloc LIST avant lui.
    var i = 12, debut = -1, fin = d.count
    while i + 8 <= d.count {
        let taille = Int(d[i + 4]) | Int(d[i + 5]) << 8 | Int(d[i + 6]) << 16 | Int(d[i + 7]) << 24
        if d[i..<i + 4] == Data("data".utf8) {
            debut = i + 8
            fin = min(d.count, taille > 0 ? debut + taille : d.count)
            break
        }
        i += 8 + taille + (taille & 1)
    }
    guard debut >= 0 else {
        journal("\(chemin) : pas de données audio")
        exit(1)
    }
    var max = 0
    d.withUnsafeBytes { (octets: UnsafeRawBufferPointer) in
        var j = debut
        while j + 1 < fin {
            let s = Int(Int16(bitPattern: UInt16(octets[j]) | UInt16(octets[j + 1]) << 8))
            if abs(s) > max { max = abs(s) }
            j += 2
        }
    }
    print(String(format: "%.1f", max == 0 ? -91.0 : 20 * log10(Double(max) / 32768)))
    exit(0)
}

// MARK: lancement

var enregistreur: Enregistreur!
var args = CommandLine.arguments.dropFirst()
func valeur() -> String {
    guard let v = args.popFirst() else { usage() }
    return v
}
var demande = ":default", sortie: String?, cheminNiveaux: String?, duree = 0.0
while let a = args.popFirst() {
    switch a {
    case "--list-devices":
        for m in micros() { print(m.nom) }
        exit(0)
    case "--peak":
        pic(valeur())
    case "--device":
        demande = valeur()
    case "--max":
        guard let v = Double(valeur()), v >= 0 else { usage() }
        duree = v
    case "--levels":
        cheminNiveaux = valeur()
    default:
        guard !a.hasPrefix("-"), sortie == nil else { usage() }
        sortie = a
    }
}
guard let sortie else { usage() }

enregistreur = Enregistreur(demande: demande, chemin: sortie, niveaux: cheminNiveaux, max: duree)
// Signaux traités sur la file de traitement : un SIGINT reçu pendant le
// démarrage attend qu'il se termine, puis finalise.
var sources: [DispatchSourceSignal] = []
for s in [SIGINT, SIGTERM] {
    signal(s, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: s, queue: traitement)
    source.setEventHandler { enregistreur.arreter() }
    source.resume()
    sources.append(source)
}
traitement.async { enregistreur.demarrer() }
// Boucle principale active : Core Audio y attache ses notifications (micro
// débranché, fréquence changée). Le port la garde ouverte.
RunLoop.main.add(Port(), forMode: .default)
RunLoop.main.run()
