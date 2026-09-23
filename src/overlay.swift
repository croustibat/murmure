import AppKit

// Murmure — pastille flottante affichée pendant la dictée.
// Onde animée + libellé + bouton stop + ✕ (annuler). L'état est lu dans un fichier :
// « recording <durée max> », « transcribing <durée estimée> », « pasting », et sa
// disparition ferme la fenêtre. Pendant l'écoute, l'onde suit le niveau RMS
// qu'écrit ffmpeg dans « levels », à côté du fichier d'état, et le libellé
// devient un compte à rebours à l'approche de la durée max (début de capture
// lu dans « started »). Pendant la transcription, les points de l'onde
// servent de jauge et s'allument un à un.

let statusPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/murmure-\(getuid())/status"
let toggleScript = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : NSString(string: "~/.local/share/murmure/murmure.sh").expandingTildeInPath
let levelsPath = (statusPath as NSString).deletingLastPathComponent + "/levels"
let startedPath = (statusPath as NSString).deletingLastPathComponent + "/started"

final class PillView: NSView {
    var phase: CGFloat = 0
    var label: String = "Vous parlez"
    var listening: Bool = true
    var progress: CGFloat = 0   // 0…1, jauge affichée hors écoute
    var level: CGFloat = 0      // 0…1, niveau de la voix pendant l'écoute
    private var stopRect: NSRect = .zero
    private var cancelRect: NSRect = .zero

    private let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    var intrinsicWidth: CGFloat {
        let w = (label as NSString).size(withAttributes: [.font: font]).width
        return 34 + 44 + 10 + w + 14 + 1 + 14 + 14 + 24 + 12
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds

        // Fond capsule
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 12,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor(calibratedWhite: 0.11, alpha: 0.96).setFill()
        path.fill()
        ctx.restoreGState()
        NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
        path.lineWidth = 1
        path.stroke()

        // Onde à gauche : amplitude portée par le niveau réel, bombée au centre
        // et légèrement ondulée pour rester vivante ; plate dans le silence.
        let bars = 8
        let barW: CGFloat = 3
        let gap: CGFloat = 3.5
        let waveX: CGFloat = 18
        let midY = r.midY
        let filled = progress * CGFloat(bars)
        for i in 0..<bars {
            let t = phase + CGFloat(i) * 0.55
            let bulge = 0.55 + 0.45 * sin(.pi * (CGFloat(i) + 0.5) / CGFloat(bars))
            let amp: CGFloat = listening ? level * bulge * (0.7 + 0.3 * sin(t)) : 0.18
            let h = 3 + amp * 13
            let x = waveX + CGFloat(i) * (barW + gap)
            let br = NSRect(x: x, y: midY - h / 2, width: barW, height: h)
            var alpha: CGFloat = 0.92
            if !listening {
                // Point allumé, en cours (partiel + léger pouls) ou éteint.
                let lit = min(max(filled - CGFloat(i), 0), 1)
                let pulse = (lit < 1 && filled > CGFloat(i) - 1) ? (sin(phase * 1.5) * 0.5 + 0.5) * 0.12 : 0
                alpha = 0.25 + lit * 0.72 + pulse
            }
            NSColor(calibratedWhite: 1.0, alpha: alpha).setFill()
            NSBezierPath(roundedRect: br, xRadius: barW / 2, yRadius: barW / 2).fill()
        }

        // Libellé
        let textX = waveX + CGFloat(bars) * (barW + gap) + 10
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(at: NSPoint(x: textX, y: midY - size.height / 2), withAttributes: attrs)

        // Séparateur + bouton stop
        let sepX = textX + size.width + 14
        NSColor(calibratedWhite: 1.0, alpha: 0.18).setFill()
        NSRect(x: sepX, y: midY - 9, width: 1, height: 18).fill()

        let sq: CGFloat = 11
        stopRect = NSRect(x: sepX + 14, y: midY - sq / 2, width: sq, height: sq)
        NSColor.white.withAlphaComponent(listening ? 0.92 : 0.35).setFill()
        NSBezierPath(roundedRect: stopRect, xRadius: 2.5, yRadius: 2.5).fill()

        // ✕ : annuler sans transcrire
        let cx: CGFloat = 9
        cancelRect = NSRect(x: stopRect.maxX + 14, y: midY - cx / 2, width: cx, height: cx)
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: cancelRect.minX, y: cancelRect.minY))
        cross.line(to: NSPoint(x: cancelRect.maxX, y: cancelRect.maxY))
        cross.move(to: NSPoint(x: cancelRect.minX, y: cancelRect.maxY))
        cross.line(to: NSPoint(x: cancelRect.maxX, y: cancelRect.minY))
        cross.lineWidth = 1.8
        cross.lineCapStyle = .round
        NSColor.white.withAlphaComponent(listening ? 0.6 : 0.2).setStroke()
        cross.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard listening else { return }
        // ✕ testé en premier : sa zone de clic touche celle du carré.
        if cancelRect.insetBy(dx: -6, dy: -10).contains(p) {
            run("cancel")
        } else if stopRect.insetBy(dx: -10, dy: -10).contains(p) {
            run("toggle")
        }
    }

    private func run(_ command: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [toggleScript, command]
        try? task.run()
    }
}

final class Controller: NSObject {
    let window: NSPanel
    let view: PillView
    private var transcribeStart: Date?
    private var estimate: TimeInterval = 3

    override init() {
        view = PillView(frame: NSRect(x: 0, y: 0, width: 220, height: 44))
        window = NSPanel(contentRect: view.frame,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        super.init()
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        reposition()
        window.orderFrontRegardless()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.view.phase += 0.22
            self.updateLevel()
            self.updateProgress()
            self.view.needsDisplay = true
        }
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.syncStatus()
        }
    }

    // Lit le dernier « RMS_level=<dB> » en fin de fichier : -55 dB (bruit de
    // fond) donne une onde plate, -20 dB (voix proche) une onde pleine.
    // Montée rapide, retombée plus douce.
    func updateLevel() {
        guard view.listening else { view.level = 0; return }
        var target: CGFloat = 0
        if let fh = FileHandle(forReadingAtPath: levelsPath) {
            let end = fh.seekToEndOfFile()
            fh.seek(toFileOffset: end > 200 ? end - 200 : 0)
            let tail = String(decoding: fh.readDataToEndOfFile(), as: UTF8.self)
            fh.closeFile()
            if let line = tail.components(separatedBy: "RMS_level=").last.flatMap({ $0.split(separator: "\n").first }),
               let db = Double(line), db.isFinite {
                target = min(max(CGFloat(db + 55) / 35, 0), 1)
            }
        }
        view.level += (target - view.level) * (target > view.level ? 0.6 : 0.15)
    }

    // Avance linéaire jusqu'à 90 % de l'estimation, puis approche asymptotique :
    // la jauge ne se remplit jamais avant que le texte soit prêt.
    func updateProgress() {
        guard let start = transcribeStart, view.progress < 1 else { return }
        let r = CGFloat(Date().timeIntervalSince(start) / estimate)
        view.progress = r < 0.9 ? r : 0.9 + 0.09 * (1 - exp(-(r - 0.9) / 0.4))
    }

    func reposition() {
        let w = max(200, view.intrinsicWidth)
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        window.setFrame(NSRect(x: f.midX - w / 2, y: f.minY + 110, width: w, height: 44),
                        display: true)
        view.frame = NSRect(x: 0, y: 0, width: w, height: 44)
    }

    // « Encore 25 s » dans les 30 dernières secondes (le dernier quart si la
    // durée max est inférieure à 2 min), nil avant.
    func countdown(max: Double?) -> String? {
        guard let max, max > 0,
              let raw = try? String(contentsOfFile: startedPath, encoding: .utf8),
              let t0 = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let left = max - (Date().timeIntervalSince1970 - t0)
        guard left <= min(30, max / 4) else { return nil }
        return "Encore \(Int(Swift.max(0, left.rounded(.up)))) s"
    }

    func syncStatus() {
        guard let raw = try? String(contentsOfFile: statusPath, encoding: .utf8) else {
            NSApp.terminate(nil); return
        }
        let parts = raw.split(whereSeparator: \.isWhitespace)
        let s = parts.first.map(String.init) ?? ""
        if s == "recording" {
            view.listening = true
            view.label = countdown(max: parts.count > 1 ? Double(parts[1]) : nil) ?? "Vous parlez"
            transcribeStart = nil
        } else if s == "transcribing" {
            view.listening = false
            view.label = "Transcription…"
            if transcribeStart == nil { transcribeStart = Date() }
            if parts.count > 1, let e = Double(parts[1].replacingOccurrences(of: ",", with: ".")), e > 0 { estimate = e }
        } else if s == "pasting" {
            view.listening = false
            view.label = "Transcription…"
            view.progress = 1
        } else {
            NSApp.terminate(nil); return
        }
        reposition()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.run()
