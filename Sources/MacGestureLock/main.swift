import AppKit
import AVKit
import LocalAuthentication

struct Config {
    let videoPath: String?

    static func load() -> Config {
        let path = UserDefaults.standard.string(forKey: "ScreensaverVideo")
            ?? ProcessInfo.processInfo.environment["SCREENSAVER_VIDEO"]
        return Config(videoPath: path)
    }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var statusItem: NSStatusItem?
    private var config = Config.load()
    private var authenticationInProgress = false

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
        menu.addItem(withTitle: "Unlock with Touch ID", action: #selector(authenticateFromMenu), keyEquivalent: "u")
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func lockFromMenu() { lock() }
    @objc private func authenticateFromMenu() { authenticateWithTouchID() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func lock() {
        config = Config.load()
        authenticationInProgress = false
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { screen in
            let view = LockView(frame: screen.frame, videoURL: videoURL())
            view.onAuthenticate = { [weak self] in self?.authenticateWithTouchID() }
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
        authenticateWithTouchID()
    }

    private func videoURL() -> URL? {
        guard let path = config.videoPath, !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    private func authenticateWithTouchID() {
        guard !windows.isEmpty, !authenticationInProgress else { return }
        authenticationInProgress = true
        setStatus("Touch ID required to unlock", color: .systemCyan)

        let context = LAContext()
        context.localizedCancelTitle = "Stay Locked"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            authenticationInProgress = false
            setStatus("Touch ID is unavailable on this Mac", color: .systemRed)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock H0Ver screen") { [weak self] success, authError in
            Task { @MainActor in
                guard let self else { return }
                self.authenticationInProgress = false
                if success {
                    self.unlock()
                } else {
                    let message = authError?.localizedDescription ?? "Touch ID failed. Try again."
                    self.setStatus(message, color: .systemOrange)
                }
            }
        }
    }

    private func setStatus(_ text: String, color: NSColor) {
        windows.compactMap { $0.contentView as? LockView }.forEach { $0.setStatus(text, color: color) }
    }

    private func unlock() {
        windows.forEach { ($0.contentView as? LockView)?.stopVideo(); $0.close() }
        windows = []
    }
}

@MainActor
final class LockView: NSView {
    var onAuthenticate: (() -> Void)?
    var onEmergencyQuit: (() -> Void)?

    private var status = "Use Touch ID to unlock"
    private var statusColor = NSColor.systemCyan
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
    }

    private func drawOverlayPanel() {
        let panel = NSRect(x: bounds.midX - 330, y: 28, width: 660, height: 132)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 18, yRadius: 18).fill()
        drawCentered("Touch ID unlock only", y: 108, size: 28, color: .white)
        drawCentered(status, y: 74, size: 18, color: statusColor)
        drawCentered("Click or press Return to retry Touch ID. Gestures are disabled. Esc ×5 or ⌘Q quits.", y: 46, size: 14, color: .lightGray)
    }

    private func drawCentered(_ text: String, y: CGFloat, size: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attrs)
        string.draw(at: CGPoint(x: bounds.midX - string.size().width / 2, y: y))
    }

    override func mouseDown(with event: NSEvent) {
        onAuthenticate?()
    }

    override func mouseDragged(with event: NSEvent) {
        // Intentionally ignored. Drawn gestures must never unlock the app.
    }

    override func mouseUp(with event: NSEvent) {
        // Intentionally ignored. Drawn gestures must never unlock the app.
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "q" {
            onEmergencyQuit?()
        } else if event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == " " {
            onAuthenticate?()
        } else if event.keyCode == 53 {
            escapeCount += 1
            setStatus("Emergency quit: press Esc \(max(0, 5 - escapeCount)) more times", color: .systemOrange)
            if escapeCount >= 5 { onEmergencyQuit?() }
        } else {
            super.keyDown(with: event)
        }
    }

    func setStatus(_ text: String, color: NSColor) {
        status = text
        statusColor = color
        needsDisplay = true
    }
}
