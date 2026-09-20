import AppKit

// Murmure — pastille flottante affichée pendant la dictée.
// Onde animée + libellé + bouton stop. L'état est lu dans un fichier :
// « recording », « transcribing », et sa disparition ferme la fenêtre.

let statusPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/murmure-\(getuid())/status"
let toggleScript = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : NSString(string: "~/.local/share/murmure/murmure.sh").expandingTildeInPath

final class PillView: NSView {
    var phase: CGFloat = 0
    var label: String = "Vous parlez"
    var listening: Bool = true
    private var stopRect: NSRect = .zero

    private let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    var intrinsicWidth: CGFloat {
        let w = (label as NSString).size(withAttributes: [.font: font]).width
        return 34 + 44 + 10 + w + 14 + 1 + 14 + 14 + 12
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

        // Onde animée à gauche
        let bars = 8
        let barW: CGFloat = 3
        let gap: CGFloat = 3.5
        let waveX: CGFloat = 18
        let midY = r.midY
        for i in 0..<bars {
            let t = phase + CGFloat(i) * 0.55
            let amp: CGFloat = listening ? (sin(t) * 0.5 + 0.5) : 0.18
            let h = 3 + amp * 13
            let x = waveX + CGFloat(i) * (barW + gap)
            let br = NSRect(x: x, y: midY - h / 2, width: barW, height: h)
            NSColor(calibratedWhite: 1.0, alpha: listening ? 0.92 : 0.45).setFill()
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
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard listening, stopRect.insetBy(dx: -10, dy: -10).contains(p) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [toggleScript]
        try? task.run()
    }
}

final class Controller: NSObject {
    let window: NSPanel
    let view: PillView

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
            self.view.needsDisplay = true
        }
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.syncStatus()
        }
    }

    func reposition() {
        let w = max(200, view.intrinsicWidth)
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        window.setFrame(NSRect(x: f.midX - w / 2, y: f.minY + 110, width: w, height: 44),
                        display: true)
        view.frame = NSRect(x: 0, y: 0, width: w, height: 44)
    }

    func syncStatus() {
        guard let raw = try? String(contentsOfFile: statusPath, encoding: .utf8) else {
            NSApp.terminate(nil); return
        }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s == "recording" {
            view.listening = true
            view.label = "Vous parlez"
        } else if s == "transcribing" {
            view.listening = false
            view.label = "Transcription…"
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
