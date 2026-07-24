import AppKit
import AVKit

struct Config {
    let phrase: [Character]
    let videoPath: String?

    static func load() -> Config {
        let phraseRaw = UserDefaults.standard.string(forKey: "UnlockPhrase")
            ?? ProcessInfo.processInfo.environment["UNLOCK_PHRASE"]
            ?? "L"
        let letters = phraseRaw.uppercased().filter { $0.isLetter }
        let path = UserDefaults.standard.string(forKey: "ScreensaverVideo")
            ?? ProcessInfo.processInfo.environment["SCREENSAVER_VIDEO"]
        return Config(phrase: Array(letters.isEmpty ? "L" : letters), videoPath: path)
    }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var statusItem: NSStatusItem?
    private var config = Config.load()
    private var progress = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeMenuBarItem()
        lock()
    }

    private func makeMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "H0Ver"
        let menu = NSMenu()
        menu.addItem(withTitle: "Lock Now", action: #selector(lockFromMenu), keyEquivalent: "l")
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func lockFromMenu() { lock() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func lock() {
        config = Config.load()
        progress = 0
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { screen in
            let view = LockView(frame: screen.frame, videoURL: videoURL())
            view.expectedText = expectedText
            view.onStroke = { [weak self, weak view] points in
                guard let self, let view else { return }
                self.handle(points: points, in: view)
            }
            view.onEmergencyQuit = { NSApp.terminate(nil) }

            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .black
            window.isOpaque = true
            window.ignoresMouseEvents = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func videoURL() -> URL? {
        guard let path = config.videoPath, !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    private var expectedText: String {
        String(config.phrase.prefix(progress)) + "·" + String(config.phrase.dropFirst(progress))
    }

    private func updatePrompt() {
        windows.compactMap { $0.contentView as? LockView }.forEach { $0.expectedText = expectedText }
    }

    private func handle(points: [CGPoint], in view: LockView) {
        let wanted = config.phrase[progress]
        let result = LetterRecognizer.recognize(points: points)
        if result == wanted {
            progress += 1
            if progress == config.phrase.count {
                unlock()
            } else {
                view.flash(message: "Matched \(wanted). Keep drawing.", success: true)
                updatePrompt()
            }
        } else {
            progress = 0
            view.flash(message: "Saw \(result.map(String.init) ?? "?"). Try again.", success: false)
            updatePrompt()
        }
    }

    private func unlock() {
        windows.forEach { ($0.contentView as? LockView)?.stopVideo(); $0.close() }
        windows = []
    }
}

@MainActor
final class LockView: NSView {
    var onStroke: (([CGPoint]) -> Void)?
    var onEmergencyQuit: (() -> Void)?
    var expectedText: String = "·L" { didSet { needsDisplay = true } }

    private var points: [CGPoint] = []
    private var banner = "Draw the unlock letters on your trackpad"
    private var bannerColor = NSColor.white
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var hasVideo = false
    private var escapeCount = 0

    init(frame frameRect: NSRect, videoURL: URL?) {
        super.init(frame: frameRect)
        wantsLayer = true
        if let videoURL {
            let player = AVPlayer(url: videoURL)
            player.isMuted = false
            player.actionAtItemEnd = .none
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            self.layer?.addSublayer(layer)
            self.player = player
            self.playerLayer = layer
            self.hasVideo = true
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            player.play()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    func stopVideo() { player?.pause() }

    override func draw(_ dirtyRect: NSRect) {
        if !hasVideo {
            NSColor.black.setFill()
            bounds.fill()
            drawCentered("H0Ver", y: bounds.midY - 35, size: 96, color: .white)
        }

        drawOverlayPanel()

        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = 7
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        NSColor.systemCyan.setStroke()
        path.stroke()
    }

    private func drawOverlayPanel() {
        let panel = NSRect(x: bounds.midX - 310, y: 28, width: 620, height: 132)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 18, yRadius: 18).fill()
        drawCentered("Unlock phrase: \(expectedText)", y: 108, size: 28, color: .systemCyan)
        drawCentered(banner, y: 74, size: 18, color: bannerColor)
        drawCentered("Drag one letter at a time. Esc ×5 or ⌘Q quits.", y: 46, size: 14, color: .lightGray)
    }

    private func drawCentered(_ text: String, y: CGFloat, size: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attrs)
        string.draw(at: CGPoint(x: bounds.midX - string.size().width / 2, y: y))
    }

    override func mouseDown(with event: NSEvent) {
        points = [convert(event.locationInWindow, from: nil)]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        points.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        points.append(convert(event.locationInWindow, from: nil))
        let stroke = points
        points.removeAll()
        needsDisplay = true
        onStroke?(stroke)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "q" {
            onEmergencyQuit?()
        } else if event.keyCode == 53 {
            escapeCount += 1
            banner = "Emergency quit: press Esc \(max(0, 5 - escapeCount)) more times"
            bannerColor = .systemOrange
            needsDisplay = true
            if escapeCount >= 5 { onEmergencyQuit?() }
        } else {
            super.keyDown(with: event)
        }
    }

    func flash(message: String, success: Bool) {
        banner = message
        bannerColor = success ? .systemGreen : .systemRed
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.banner = "Draw the unlock letters on your trackpad"
            self?.bannerColor = .white
            self?.needsDisplay = true
        }
    }
}

enum LetterRecognizer {
    static func recognize(points: [CGPoint]) -> Character? {
        let normalized = normalize(points)
        guard normalized.count >= 8 else { return nil }
        return templates.min { score(normalized, normalize($0.value)) < score(normalized, normalize($1.value)) }?.key
    }

    private static func score(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        zip(a, b).map { hypot($0.x - $1.x, $0.y - $1.y) }.reduce(0, +) / CGFloat(min(a.count, b.count))
    }

    private static func normalize(_ input: [CGPoint], count: Int = 64) -> [CGPoint] {
        let sampled = resample(input, count: count)
        guard let minX = sampled.map(\.x).min(), let maxX = sampled.map(\.x).max(), let minY = sampled.map(\.y).min(), let maxY = sampled.map(\.y).max() else { return [] }
        let scale = max(maxX - minX, maxY - minY, 1)
        return sampled.map { CGPoint(x: (($0.x - minX) / scale) - 0.5, y: (($0.y - minY) / scale) - 0.5) }
    }

    private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > 1 else { return points }
        let distances = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = distances.reduce(0, +)
        guard total > 0 else { return Array(repeating: points[0], count: count) }
        return (0..<count).compactMap { i in
            let target = total * CGFloat(i) / CGFloat(count - 1)
            var covered: CGFloat = 0
            for j in distances.indices {
                if covered + distances[j] >= target {
                    let t = (target - covered) / max(distances[j], 0.0001)
                    return CGPoint(x: points[j].x + (points[j + 1].x - points[j].x) * t, y: points[j].y + (points[j + 1].y - points[j].y) * t)
                }
                covered += distances[j]
            }
            return points.last
        }
    }

    private static let templates: [Character: [CGPoint]] = {
        var t: [Character: [CGPoint]] = [:]
        t["L"] = [p(0, 1), p(0, 0), p(0.8, 0)]
        t["I"] = [p(0.5, 1), p(0.5, 0)]
        t["V"] = [p(0, 1), p(0.5, 0), p(1, 1)]
        t["Z"] = [p(0, 1), p(1, 1), p(0, 0), p(1, 0)]
        t["M"] = [p(0, 0), p(0, 1), p(0.5, 0.45), p(1, 1), p(1, 0)]
        t["N"] = [p(0, 0), p(0, 1), p(1, 0), p(1, 1)]
        t["C"] = arc(40, 320)
        t["O"] = arc(0, 360)
        return t
    }()

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func arc(_ start: Int, _ end: Int) -> [CGPoint] {
        stride(from: start, through: end, by: 20).map { angle in
            let radians = CGFloat(angle) * .pi / 180
            return CGPoint(x: 0.5 + 0.5 * cos(radians), y: 0.5 + 0.5 * sin(radians))
        }
    }
}
