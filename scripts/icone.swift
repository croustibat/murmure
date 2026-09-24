// Murmure — générateur de l'icône de l'app.
//
//   swift scripts/icone.swift [--variante N] [--planche FICHIER.png]
//
// Dessine l'icône (onde de barres blanches arrondies, comme la pastille, sur
// fond sombre) à toutes les tailles d'un .iconset, puis produit :
//   app/Murmure.icns               via iconutil, copié par install.sh ;
//   site/public/icone-512.png      icône macOS en 512 px, pour la landing ;
//   site/public/favicon.png        32 px, la forme occupe tout le cadre ;
//   site/public/apple-touch-icon.png  180 px, carré plein (iOS arrondit lui-même).
// Le dessin ne dépend que du code : relancer le script régénère à l'identique les
// fichiers versionnés.
//
// Grille Apple (macOS 11+) : forme « squircle » à coins continus de 824 px dans un
// canevas de 1024, marges de 100 px, ombre portée vers le bas.
// Aux petites tailles, l'onde passe à moins de barres, plus épaisses et calées
// sur les pixels, pour rester lisible à 16 px.
//
// --variante choisit le fond (2 par défaut, la variante retenue) ; --planche écrit en plus un aperçu des
// variantes à 1024, 256, 64, 32 et 16 px, sur fond clair et sombre.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Variantes

struct Variante {
    let nom: String
    let fond: [CGColor]          // dégradé du haut vers le bas (une couleur : uni)
    let fondDiagonal: Bool       // dégradé du coin haut gauche au coin bas droit
    let barres: [CGColor]?       // dégradé horizontal de l'onde ; nil : blanc
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let variantes: [Variante] = [
    // 1. Presque noir, comme la pastille (blanc à 11 %).
    Variante(nom: "fond presque noir", fond: [rgb(0x2A2A2D), rgb(0x141415)],
             fondDiagonal: false, barres: nil),
    // 2. Dégradé profond indigo → violet.
    Variante(nom: "dégradé indigo → violet", fond: [rgb(0x4338CA), rgb(0x6D28D9), rgb(0x3B0764)],
             fondDiagonal: true, barres: nil),
    // 3. Onde en dégradé cyan → violet → rose sur fond bleu nuit.
    Variante(nom: "onde en dégradé sur fond nuit", fond: [rgb(0x1E2233), rgb(0x0B0D16)],
             fondDiagonal: false, barres: [rgb(0x5EEAD4), rgb(0x818CF8), rgb(0xF0ABFC)]),
]

// MARK: - Forme

// Rectangle à coins continus (courbure sans cassure, comme les icônes Apple) :
// chaque coin s'étend sur 1,528 × rayon, avec les points de contrôle du
// « continuous corner » d'UIKit.
func squircle(_ r: CGRect, rayon: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k = rayon
    // Coin c, e1 : vers l'intérieur le long du côté d'arrivée, e2 : le long du côté de départ.
    func coin(_ c: CGPoint, _ e1: CGVector, _ e2: CGVector, premier: Bool) {
        func pt(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
            CGPoint(x: c.x + (a * e1.dx + b * e2.dx) * k, y: c.y + (a * e1.dy + b * e2.dy) * k)
        }
        if premier { p.move(to: pt(1.52866483, 0)) } else { p.addLine(to: pt(1.52866483, 0)) }
        p.addCurve(to: pt(0.63149399, 0.07491100), control1: pt(1.08849296, 0), control2: pt(0.86840694, 0))
        p.addCurve(to: pt(0.07491100, 0.63149399), control1: pt(0.37282392, 0.16905899), control2: pt(0.16905899, 0.37282392))
        p.addCurve(to: pt(0, 1.52866483), control1: pt(0, 0.86840694), control2: pt(0, 1.08849296))
    }
    coin(CGPoint(x: r.maxX, y: r.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1), premier: true)
    coin(CGPoint(x: r.maxX, y: r.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0), premier: false)
    coin(CGPoint(x: r.minX, y: r.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1), premier: false)
    coin(CGPoint(x: r.minX, y: r.minY), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0), premier: false)
    p.closeSubpath()
    return p
}

// MARK: - Onde

// Hauteurs relatives des barres (1 = la plus haute), bombées au centre comme la
// pastille, un peu asymétriques pour évoquer une voix plutôt qu'un égaliseur.
struct Onde {
    let hauteurs: [CGFloat]
    let largeur: CGFloat       // fraction du côté de la forme
    let ecart: CGFloat         // idem
    let hauteurMax: CGFloat    // idem
}

let ondeGrande = Onde(hauteurs: [0.30, 0.56, 0.86, 1.00, 0.70, 0.46, 0.26],
                      largeur: 0.064, ecart: 0.044, hauteurMax: 0.56)
let ondeMoyenne = Onde(hauteurs: [0.42, 0.80, 1.00, 0.66, 0.36],
                       largeur: 0.092, ecart: 0.062, hauteurMax: 0.60)

// Aux petites tailles, dimensions en pixels entiers pour une onde nette.
struct OndePixels { let hauteurs: [Int]; let largeur: Int; let ecart: Int }

func ondePixels(_ px: Int) -> OndePixels? {
    switch px {
    case ...16: return OndePixels(hauteurs: [4, 7, 9, 6, 3], largeur: 1, ecart: 1)
    case ...32: return OndePixels(hauteurs: [6, 12, 16, 10, 5], largeur: 2, ecart: 2)
    case ...64: return OndePixels(hauteurs: [12, 24, 30, 20, 10], largeur: 4, ecart: 3)
    default: return nil
    }
}

// Rectangles des barres, dans le repère du canevas, centrés sur la forme.
func barres(forme f: CGRect, px: Int) -> [CGRect] {
    if let o = ondePixels(px) {
        let total = o.hauteurs.count * o.largeur + (o.hauteurs.count - 1) * o.ecart
        let x0 = (f.midX - CGFloat(total) / 2).rounded()
        return o.hauteurs.enumerated().map { i, h in
            CGRect(x: x0 + CGFloat(i * (o.largeur + o.ecart)),
                   y: (f.midY - CGFloat(h) / 2).rounded(),
                   width: CGFloat(o.largeur), height: CGFloat(h))
        }
    }
    let o = px >= 128 ? ondeGrande : ondeMoyenne
    let c = f.width
    let w = o.largeur * c, g = o.ecart * c
    let total = CGFloat(o.hauteurs.count) * w + CGFloat(o.hauteurs.count - 1) * g
    return o.hauteurs.enumerated().map { i, h in
        let hh = h * o.hauteurMax * c
        return CGRect(x: f.midX - total / 2 + CGFloat(i) * (w + g), y: f.midY - hh / 2,
                      width: w, height: hh)
    }
}

// MARK: - Dessin

enum Cadre {
    case macos     // grille Apple : forme de 824/1024, marges et ombre
    case plein     // forme sur tout le cadre, sans ombre (favicon)
    case carre     // fond plein cadre, sans arrondi (apple-touch-icon)
}

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func dessiner(_ v: Variante, px: Int, cadre: Cadre = .macos) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let s = CGFloat(px) / 1024
    let forme: CGRect
    let chemin: CGPath
    switch cadre {
    case .macos:
        forme = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        chemin = squircle(forme, rayon: 185.4 * s)
    case .plein:
        forme = CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
        chemin = squircle(forme, rayon: 185.4 / 824 * CGFloat(px))
    case .carre:
        forme = CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
        chemin = CGPath(rect: forme, transform: nil)
    }

    // Ombre portée (grille Apple : vers le bas, diffuse, discrète).
    if cadre == .macos {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 20 * s,
                      color: CGColor(gray: 0, alpha: 0.32))
        ctx.addPath(chemin)
        ctx.setFillColor(v.fond.last!)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Fond
    ctx.saveGState()
    ctx.addPath(chemin)
    ctx.clip()
    if v.fond.count == 1 {
        ctx.setFillColor(v.fond[0])
        ctx.fill(forme)
    } else {
        let lieux = (0..<v.fond.count).map { CGFloat($0) / CGFloat(v.fond.count - 1) }
        let grad = CGGradient(colorsSpace: srgb, colors: v.fond as CFArray, locations: lieux)!
        let debut = v.fondDiagonal ? CGPoint(x: forme.minX, y: forme.maxY) : CGPoint(x: forme.midX, y: forme.maxY)
        let fin = v.fondDiagonal ? CGPoint(x: forme.maxX, y: forme.minY) : CGPoint(x: forme.midX, y: forme.minY)
        ctx.drawLinearGradient(grad, start: debut, end: fin, options: [])
    }
    // Lueur douce au-dessus du centre, pour donner un peu de relief.
    let lueur = CGGradient(colorsSpace: srgb,
                           colors: [CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(lueur, startCenter: CGPoint(x: forme.midX, y: forme.minY + forme.height * 0.78),
                           startRadius: 0,
                           endCenter: CGPoint(x: forme.midX, y: forme.minY + forme.height * 0.78),
                           endRadius: forme.width * 0.75, options: [])
    ctx.restoreGState()

    // Liseré clair, comme le contour de la pastille (inutile aux petites tailles).
    if cadre != .carre && px >= 64 {
        ctx.saveGState()
        ctx.addPath(chemin)
        ctx.clip()
        ctx.addPath(chemin)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
        ctx.setLineWidth(max(1, 4 * s) * 2)   // moitié intérieure seulement, grâce au clip
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Onde
    let rects = barres(forme: cadre == .macos ? forme : forme.insetBy(dx: forme.width * 0.03, dy: forme.width * 0.03),
                       px: cadre == .macos ? px : px * 824 / 1024)
    ctx.saveGState()
    for r in rects {
        let rayon = r.width / 2
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: rayon, cornerHeight: min(rayon, r.height / 2), transform: nil))
    }
    if let couleurs = v.barres {
        ctx.clip()
        let lieux = (0..<couleurs.count).map { CGFloat($0) / CGFloat(couleurs.count - 1) }
        let grad = CGGradient(colorsSpace: srgb, colors: couleurs as CFArray, locations: lieux)!
        let x0 = rects.first!.minX, x1 = rects.last!.maxX
        ctx.drawLinearGradient(grad, start: CGPoint(x: x0, y: 0), end: CGPoint(x: x1, y: 0), options: [])
    } else {
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
        ctx.fillPath()
    }
    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - Fichiers

func ecrirePNG(_ image: CGImage, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("écriture impossible : \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("écriture impossible : \(url.path)") }
}

func planche(_ url: URL) {
    let tailles = [1024, 256, 64, 32, 16]
    let marge = 48, ecart = 40, entete = 56
    let petites = tailles.dropFirst()
    let largeurPetites = petites.reduce(0, +) + ecart * (petites.count - 1)
    let bande = largeurPetites + 2 * ecart          // bande claire puis bande sombre
    let largeur = marge + 1024 + ecart + bande * 2 + marge
    let rangee = entete + 1024 + ecart
    let hauteur = marge + rangee * variantes.count
    let ctx = CGContext(data: nil, width: largeur, height: hauteur, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(rgb(0xF2F2F4))
    ctx.fill(CGRect(x: 0, y: 0, width: largeur, height: hauteur))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let police = NSFont.systemFont(ofSize: 30, weight: .semibold)
    let policeTaille = NSFont.systemFont(ofSize: 18, weight: .regular)

    for (n, v) in variantes.enumerated() {
        let haut = hauteur - marge - n * rangee                      // haut de la rangée
        ("Variante \(n + 1) — \(v.nom)" as NSString).draw(
            at: NSPoint(x: marge, y: haut - 38),
            withAttributes: [.font: police, .foregroundColor: NSColor(white: 0.1, alpha: 1)])
        let base = haut - entete - 1024                              // bas de l'image 1024
        ctx.draw(dessiner(v, px: 1024), in: CGRect(x: marge, y: base, width: 1024, height: 1024))
        // Petites tailles à l'échelle 1:1, sur fond clair puis sur fond sombre.
        for (i, fond) in [rgb(0xFFFFFF), rgb(0x1E1E20)].enumerated() {
            let bx = marge + 1024 + ecart + i * bande
            let hautBande = 256 + 2 * ecart + 30
            let by = base + 1024 - hautBande
            ctx.setFillColor(fond)
            let basBande = by - 3 * ecart - 256 - 20
            ctx.fill(CGRect(x: bx, y: basBande, width: bande, height: base + 1024 - basBande))
            // Loupe ×8 sans lissage : 32 puis 16 px, pixel par pixel.
            ctx.saveGState()
            ctx.interpolationQuality = .none
            var lx = bx + ecart
            for t in [32, 16] {
                ctx.draw(dessiner(v, px: t), in: CGRect(x: lx, y: by - ecart - 256 + (256 - t * 8) / 2,
                                                        width: t * 8, height: t * 8))
                lx += t * 8 + ecart
            }
            ctx.restoreGState()
            ("loupe ×8 : 32 et 16 px" as NSString).draw(
                at: NSPoint(x: bx + ecart, y: by - 2 * ecart - 256 - 10),
                withAttributes: [.font: policeTaille,
                                 .foregroundColor: i == 0 ? NSColor(white: 0.35, alpha: 1) : NSColor(white: 0.7, alpha: 1)])
            var x = bx + ecart
            for t in petites {
                let y = by + ecart + 30 + (256 - t) / 2
                ctx.draw(dessiner(v, px: t), in: CGRect(x: x, y: y, width: t, height: t))
                ("\(t)" as NSString).draw(
                    at: NSPoint(x: x, y: by + 12),
                    withAttributes: [.font: policeTaille,
                                     .foregroundColor: i == 0 ? NSColor(white: 0.35, alpha: 1) : NSColor(white: 0.7, alpha: 1)])
                x += t + ecart
            }
        }
    }
    NSGraphicsContext.current = nil
    ecrirePNG(ctx.makeImage()!, url)
}

// MARK: - Programme

var numero = 2   // variante retenue : dégradé indigo → violet
var cheminPlanche: String?
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "--variante":
        guard let n = args.next().flatMap(Int.init), (1...variantes.count).contains(n) else {
            fatalError("--variante attend un numéro de 1 à \(variantes.count)")
        }
        numero = n
    case "--planche":
        guard let p = args.next() else { fatalError("--planche attend un chemin de fichier .png") }
        cheminPlanche = p
    default:
        FileHandle.standardError.write("usage : swift scripts/icone.swift [--variante N] [--planche FICHIER.png]\n".data(using: .utf8)!)
        exit(2)
    }
}

let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let v = variantes[numero - 1]

let temp = FileManager.default.temporaryDirectory
    .appendingPathComponent("murmure-icone-\(getpid())", isDirectory: true)
let iconset = temp.appendingPathComponent("Murmure.iconset", isDirectory: true)
defer { try? FileManager.default.removeItem(at: temp) }
for base in [16, 32, 128, 256, 512] {
    ecrirePNG(dessiner(v, px: base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    ecrirePNG(dessiner(v, px: base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let icns = racine.appendingPathComponent("app/Murmure.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", icns.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil a échoué") }
print("\(icns.path) (variante \(numero) : \(v.nom))")

let site = racine.appendingPathComponent("site/public")
ecrirePNG(dessiner(v, px: 512), site.appendingPathComponent("icone-512.png"))
ecrirePNG(dessiner(v, px: 32, cadre: .plein), site.appendingPathComponent("favicon.png"))
ecrirePNG(dessiner(v, px: 180, cadre: .carre), site.appendingPathComponent("apple-touch-icon.png"))
print("\(site.path)/{icone-512,favicon,apple-touch-icon}.png")

if let p = cheminPlanche {
    let url = URL(fileURLWithPath: p)
    planche(url)
    print(url.path)
}
