import AppKit
import AVKit
import LocalAuthentication

struct Config {
    let videoPath: String?
    let appPassword: String

    static func load() -> Config {
        let path = UserDefaults.standard.string(forKey: "ScreensaverVideo")
            ?? ProcessInfo.processInfo.environment["SCREENSAVER_VIDEO"]
        let password = UserDefaults.standard.string(forKey: "AppPassword")
            ?? ProcessInfo.processInfo.environment["LOCK_PASSWORD"]
            ?? "hover"
        return Config(videoPath: path, appPassword: password)
    }
}

@main
@MainActor
enum MacGestureLockMain {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var statusItem: NSStatusItem?
    private var config = Config.load()
    private var authenticationInProgress = false
    private var keepFrontTimer: Timer?
    private var eventMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        makeMenuBarItem()
        installEventMonitors()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
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
    @objc private func quit() {
        restorePresentationOptions()
        NSApplication.shared.terminate(nil)
    }
    @objc private func screensChanged() { if !windows.isEmpty { lock() } }

    private func lock() {
        config = Config.load()
        authenticationInProgress = false
        applyLockedPresentationOptions()
        windows.forEach { ($0.contentView as? LockView)?.stopVideo(); $0.close() }
        windows = NSScreen.screens.map(makeWindow)
        startKeepFrontTimer()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let view = LockView(frame: screen.frame, videoURL: videoURL())
        view.onAuthenticate = { [weak self] in self?.authenticateWithTouchID() }
        view.onPasswordSubmit = { [weak self] password in self?.validate(password: password) }
        view.onEmergencyQuit = { [weak self] in
            self?.restorePresentationOptions()
            NSApplication.shared.terminate(nil)
        }

        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.backgroundColor = .black
        window.isOpaque = true
        window.ignoresMouseEvents = false
        window.canHide = false
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func startKeepFrontTimer() {
        keepFrontTimer?.invalidate()
        keepFrontTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reassertOverlay() }
        }
    }

    private func reassertOverlay() {
        guard !windows.isEmpty else { return }
        for window in windows {
            window.level = .screenSaver
            window.orderFrontRegardless()
            window.contentView?.needsDisplay = true
        }
    }

    private func applyLockedPresentationOptions() {
        NSApplication.shared.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication,
            .disableMenuBarTransparency
        ]
    }

    private func restorePresentationOptions() {
        NSApplication.shared.presentationOptions = []
    }

    private func installEventMonitors() {
        let swallowed: NSEvent.EventTypeMask = [.scrollWheel, .swipe, .magnify, .rotate, .smartMagnify, .gesture]
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: swallowed) { [weak self] event in
            guard let self, !self.windows.isEmpty else { return event }
            self.reassertOverlay()
            return nil
        } as Any)
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [weak self] event in
            guard let self, !self.windows.isEmpty else { return event }
            self.setStatus("Type password and press Return, or press T for Touch ID.", color: .systemOrange)
            return nil
        } as Any)
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
        setStatus("Use Touch ID or Mac password to unlock", color: .systemCyan)

        let context = LAContext()
        context.localizedCancelTitle = "Stay Locked"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationInProgress = false
            setStatus("Mac authentication unavailable.", color: .systemRed)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock H0Ver screen") { [weak self] success, authError in
            Task { @MainActor in
                guard let self else { return }
                self.authenticationInProgress = false
                if success {
                    self.unlock()
                } else {
                    self.setStatus(authError?.localizedDescription ?? "Touch ID failed. Still locked.", color: .systemOrange)
                }
            }
        }
    }

    private func setStatus(_ text: String, color: NSColor) {
        windows.compactMap { $0.contentView as? LockView }.forEach { $0.setStatus(text, color: color) }
    }

    private func validate(password: String) {
        guard !windows.isEmpty else { return }
        if password == config.appPassword {
            unlock()
        } else {
            windows.compactMap { $0.contentView as? LockView }.forEach { $0.clearPassword() }
            setStatus("Wrong password. Try again.", color: .systemRed)
        }
    }

    private func unlock() {
        keepFrontTimer?.invalidate()
        keepFrontTimer = nil
        windows.forEach { ($0.contentView as? LockView)?.stopVideo(); $0.close() }
        windows = []
        restorePresentationOptions()
    }
}

@MainActor
final class LockView: NSView {
    var onAuthenticate: (() -> Void)?
    var onPasswordSubmit: ((String) -> Void)?
    var onEmergencyQuit: (() -> Void)?

    private var status = "Type password, press Return, or press T for Touch ID"
    private var statusColor = NSColor.white
    private var passwordBuffer = ""
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
        let panel = NSRect(x: bounds.midX - 370, y: 28, width: 740, height: 162)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 18, yRadius: 18).fill()
        drawCentered("Password or Touch ID unlock", y: 138, size: 28, color: .systemCyan)
        drawPasswordField(y: 98)
        drawCentered(status, y: 72, size: 17, color: statusColor)
        drawCentered("Type password directly. Press T for Touch ID. Clicks, gestures, and swipes are disabled.", y: 48, size: 14, color: .lightGray)
        drawCentered("Esc ×5 or ⌘Q quits for testing.", y: 30, size: 14, color: .lightGray)
    }

    private func drawPasswordField(y: CGFloat) {
        let field = NSRect(x: bounds.midX - 170, y: y - 8, width: 340, height: 34)
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: field, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        NSBezierPath(roundedRect: field, xRadius: 8, yRadius: 8).stroke()
        let bullets = passwordBuffer.isEmpty ? "Password" : String(repeating: "•", count: passwordBuffer.count)
        drawCentered(bullets, y: y, size: 18, color: passwordBuffer.isEmpty ? .lightGray : .white)
    }

    private func drawCentered(_ text: String, y: CGFloat, size: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attrs)
        string.draw(at: CGPoint(x: bounds.midX - string.size().width / 2, y: y))
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.command), key == "q" {
            onEmergencyQuit?()
        } else if key == "t" && passwordBuffer.isEmpty {
            onAuthenticate?()
        } else if event.keyCode == 36 || event.keyCode == 76 {
            if passwordBuffer.isEmpty {
                onAuthenticate?()
            } else {
                onPasswordSubmit?(passwordBuffer)
            }
        } else if event.keyCode == 51 {
            if !passwordBuffer.isEmpty { passwordBuffer.removeLast() }
            setStatus("Type password, press Return, or press T for Touch ID", color: .white)
        } else if event.keyCode == 53 {
            escapeCount += 1
            setStatus("Emergency quit: press Esc \(max(0, 5 - escapeCount)) more times", color: .systemOrange)
            if escapeCount >= 5 { onEmergencyQuit?() }
        } else if let chars = event.characters, !chars.isEmpty, !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) {
            passwordBuffer.append(contentsOf: chars)
            setStatus("Press Return to unlock, or Backspace to edit.", color: .white)
        } else {
            setStatus("Shortcut ignored. Still locked.", color: .systemOrange)
        }
    }

    func setStatus(_ text: String, color: NSColor) {
        status = text
        statusColor = color
        needsDisplay = true
    }

    func clearPassword() {
        passwordBuffer = ""
        needsDisplay = true
    }
}
