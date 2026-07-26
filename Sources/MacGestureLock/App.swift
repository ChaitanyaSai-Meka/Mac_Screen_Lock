import AppKit
import AVKit
import LocalAuthentication

// MARK: - Configuration

struct Config {
    let videoPath: String?
    let appPassword: String
    let maxAttempts: Int
    let lockoutBaseDuration: Int

    /// Load config with priority: UserDefaults → .env file → environment variables → defaults
    static func load() -> Config {
        let env = loadDotEnv()
        let defaults = UserDefaults.standard

        let path = defaults.string(forKey: "ScreensaverVideo")
            ?? env["VIDEO_PATH"]
            ?? ProcessInfo.processInfo.environment["SCREENSAVER_VIDEO"]

        let password = defaults.string(forKey: "AppPassword")
            ?? env["LOCK_PASSWORD"]
            ?? ProcessInfo.processInfo.environment["LOCK_PASSWORD"]
            ?? "hover"

        let maxAttempts = defaults.integer(forKey: "MaxAttempts")
        let lockoutBase = defaults.integer(forKey: "LockoutDuration")

        return Config(
            videoPath: path,
            appPassword: password,
            maxAttempts: maxAttempts > 0 ? maxAttempts : 5,
            lockoutBaseDuration: lockoutBase > 0 ? lockoutBase : 10
        )
    }

    /// Parse .env file from the executable's directory or common locations
    private static func loadDotEnv() -> [String: String] {
        let candidates = [
            (ProcessInfo.processInfo.arguments.first.map { ($0 as NSString).deletingLastPathComponent } ?? ".") + "/.env",
            (ProcessInfo.processInfo.arguments.first.map {
                let dir = ($0 as NSString).deletingLastPathComponent
                return (dir as NSString).appendingPathComponent("../../.env")
            } ?? ""),
            FileManager.default.currentDirectoryPath + "/.env"
        ]

        for candidate in candidates {
            let resolved = (candidate as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: resolved),
                  let content = try? String(contentsOfFile: resolved, encoding: .utf8)
            else { continue }

            var result: [String: String] = [:]
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                if !value.isEmpty {
                    result[key] = value
                }
            }
            return result
        }
        return [:]
    }
}

// MARK: - App Entry Point

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

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var statusItem: NSStatusItem?
    private var config = Config.load()
    private var authenticationInProgress = false
    private var keepFrontTimer: Timer?
    private var eventMonitors: [Any] = []

    // Lockout state
    private var failedAttempts = 0
    private var lockedOut = false
    private var lockoutTimer: Timer?
    private var maxAttempts: Int { config.maxAttempts }
    private var lockoutDuration: TimeInterval {
        Double(config.lockoutBaseDuration) * Double(min(failedAttempts - maxAttempts + 1, 6))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        makeMenuBarItem()
        installEventMonitors()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        GlobalHotkeyManager.shared.register()
        lock()
    }
    
    func lockScreen() {
        lock()
    }

    private func makeMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "H0Ver"
        let menu = NSMenu()
        let lockItem = menu.addItem(withTitle: "Lock Now", action: #selector(lockFromMenu), keyEquivalent: "L")
        lockItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func lockFromMenu() { lock() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func quit() {
        restorePresentationOptions()
        NSApplication.shared.terminate(nil)
    }
    @objc private func screensChanged() { if !windows.isEmpty { lock() } }

    private func lock() {
        config = Config.load()
        authenticationInProgress = false
        applyLockedPresentationOptions()
        windows.forEach { ($0.contentView as? LockView)?.cleanup(); $0.close() }
        windows = NSScreen.screens.map(makeWindow)
        startKeepFrontTimer()
        NSApplication.shared.activate(ignoringOtherApps: true)
        reassertFirstResponder()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let mode = UserDefaults.standard.integer(forKey: "BackgroundMode")
        let view = LockView(frame: screen.frame, videoURL: videoURL(), backgroundMode: mode)
        view.onAuthenticate = { [weak self] in self?.authenticateWithTouchID() }
        view.onPasswordSubmit = { [weak self] password in self?.validate(password: password) }
        view.onEmergencyQuit = { [weak self] in
            self?.restorePresentationOptions()
            NSApplication.shared.terminate(nil)
        }
        view.isLockedOut = { [weak self] in self?.lockedOut ?? false }

        let window = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
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
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reassertOverlay() }
        }
        RunLoop.main.add(timer, forMode: .common)
        keepFrontTimer = timer
    }

    private func reassertOverlay() {
        guard !windows.isEmpty else { return }
        for window in windows {
            window.level = .screenSaver
            window.orderFrontRegardless()
        }
        reassertFirstResponder()
    }

    private func reassertFirstResponder() {
        guard let keyWindow = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return }
        if let lockView = keyWindow.contentView as? LockView {
            if keyWindow.firstResponder !== lockView {
                keyWindow.makeFirstResponder(lockView)
            }
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
        guard !windows.isEmpty, !authenticationInProgress, !lockedOut else { return }
        authenticationInProgress = true
        setStatus("Waiting for Touch ID...", color: NSColor.systemCyan)

        let context = LAContext()
        context.localizedCancelTitle = "Stay Locked"
        context.localizedFallbackTitle = "Enter Mac Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationInProgress = false
            setStatus("Biometrics unavailable", color: NSColor.systemRed)
            reassertFirstResponder()
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock H0Ver screen") { [weak self] success, authError in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authenticationInProgress = false
                if success {
                    self.performUnlock()
                } else {
                    self.setStatus(authError?.localizedDescription ?? "Authentication cancelled.", color: NSColor.systemOrange)
                    self.reassertFirstResponder()
                    self.reassertOverlay()
                }
            }
        }
    }

    private func setStatus(_ text: String, color: NSColor) {
        windows.compactMap { $0.contentView as? LockView }.forEach { $0.setStatus(text, color: color) }
    }

    private func validate(password: String) {
        guard !windows.isEmpty, !lockedOut else { return }

        if password.isEmpty {
            authenticateWithTouchID()
            return
        }

        if password == config.appPassword {
            failedAttempts = 0
            performUnlock()
        } else {
            failedAttempts += 1
            windows.compactMap { $0.contentView as? LockView }.forEach { $0.shakeAndClear() }

            if failedAttempts >= maxAttempts {
                startLockout()
            } else {
                let remaining = maxAttempts - failedAttempts
                setStatus("Wrong password — \(remaining) attempt\(remaining == 1 ? "" : "s") left", color: NSColor.systemRed)
            }
        }
    }

    private var lockoutRemaining = 0

    private func startLockout() {
        lockedOut = true
        let duration = lockoutDuration
        lockoutRemaining = Int(duration)

        windows.compactMap { $0.contentView as? LockView }.forEach { $0.setLockedOut(true) }
        setStatus("Too many attempts \u{2014} wait \(lockoutRemaining)s", color: NSColor.systemRed)

        lockoutTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lockoutRemaining -= 1
                if self.lockoutRemaining <= 0 {
                    self.lockoutTimer?.invalidate()
                    self.lockoutTimer = nil
                    self.lockedOut = false
                    self.windows.compactMap { $0.contentView as? LockView }.forEach { $0.setLockedOut(false) }
                    self.setStatus("", color: .white)
                } else {
                    self.setStatus("Too many attempts \u{2014} wait \(self.lockoutRemaining)s", color: NSColor.systemRed)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        lockoutTimer = timer
    }

    private func performUnlock() {
        lockoutTimer?.invalidate()
        lockoutTimer = nil
        lockedOut = false
        failedAttempts = 0

        // Fade out, stay in menu bar
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            for window in self.windows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.keepFrontTimer?.invalidate()
                self.keepFrontTimer = nil
                self.windows.forEach { ($0.contentView as? LockView)?.cleanup(); $0.close() }
                self.windows = []
                self.restorePresentationOptions()
            }
        })
    }
}

// MARK: - KeyableWindow

/// Borderless windows return false for canBecomeKey/canBecomeMain by default,
/// which prevents them from receiving keyboard events.
@MainActor
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - LockView

@MainActor
final class LockView: NSView {
    var onAuthenticate: (() -> Void)?
    var onPasswordSubmit: ((String) -> Void)?
    var onEmergencyQuit: (() -> Void)?
    var isLockedOut: (() -> Bool)?

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var hasVideo = false
    private let overlayView: OverlayView

    init(frame frameRect: NSRect, videoURL: URL?, backgroundMode: Int = 0) {
        overlayView = OverlayView(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        wantsLayer = true

        if backgroundMode == 1 {
            let gradientView = AnimatedGradientView(frame: bounds)
            gradientView.autoresizingMask = [.width, .height]
            addSubview(gradientView)
            self.hasVideo = true
        } else if let videoURL {
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

        overlayView.autoresizingMask = [.width, .height]
        overlayView.hasVideo = hasVideo
        addSubview(overlayView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    func cleanup() {
        player?.pause()
        overlayView.stopClock()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
    }

    override func keyDown(with event: NSEvent) {
        // Block all input during lockout
        if isLockedOut?() == true { return }

        let key = event.charactersIgnoringModifiers?.lowercased()
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.command), key == "q" {
            onEmergencyQuit?()
        } else if key == "t" && modifiers.contains(.function) {
            onAuthenticate?()
        } else if event.keyCode == 36 || event.keyCode == 76 {
            if overlayView.passwordBuffer.isEmpty {
                onAuthenticate?()
            } else {
                onPasswordSubmit?(overlayView.passwordBuffer)
            }
        } else if event.keyCode == 51 {
            if !overlayView.passwordBuffer.isEmpty { overlayView.passwordBuffer.removeLast() }
            overlayView.isFocused = !overlayView.passwordBuffer.isEmpty
            setStatus("", color: .white)
        } else if event.keyCode == 53 {
            overlayView.escapeCount += 1
            setStatus("Emergency quit: Esc x\(max(0, 5 - overlayView.escapeCount)) more", color: NSColor.systemOrange)
            if overlayView.escapeCount >= 5 { onEmergencyQuit?() }
        } else if let chars = event.characters, !chars.isEmpty,
                  !modifiers.contains(.command), !modifiers.contains(.control) {
            overlayView.escapeCount = 0
            overlayView.passwordBuffer.append(contentsOf: chars)
            overlayView.isFocused = true
            setStatus("", color: .white)
        }
    }

    func setStatus(_ text: String, color: NSColor) {
        overlayView.status = text
        overlayView.statusColor = color
    }

    func clearPassword() {
        overlayView.passwordBuffer = ""
        overlayView.isFocused = false
    }

    var isPasswordEmpty: Bool {
        return overlayView.passwordBuffer.isEmpty
    }

    func setLockedOut(_ locked: Bool) {
        overlayView.isLockedOut = locked
    }

    func shakeAndClear() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.4
        animation.values = [0, -12, 12, -10, 10, -6, 6, -3, 3, 0]
        overlayView.layer?.add(animation, forKey: "shake")
        clearPassword()
    }
}

// MARK: - OverlayView

/// Transparent overlay that draws the lock UI above the video.
@MainActor
final class OverlayView: NSView {
    var status = "" { didSet { textLayer.needsDisplay = true } }
    var statusColor = NSColor.white { didSet { textLayer.needsDisplay = true } }
    var passwordBuffer = "" { didSet { textLayer.needsDisplay = true } }
    var escapeCount = 0
    var isFocused = false { didSet { updateGlassBorder(); textLayer.needsDisplay = true } }
    var isLockedOut = false { didSet { updateGlassBorder(); textLayer.needsDisplay = true } }
    var hasVideo = false

    private let glassView: NSVisualEffectView
    private let textLayer: PasswordTextView
    private var clockTimer: Timer?

    private let fieldW: CGFloat = 280
    private let fieldH: CGFloat = 36

    override init(frame frameRect: NSRect) {
        let glassFrame = NSRect(
            x: frameRect.width / 2 - 140,
            y: 22,
            width: 280,
            height: 36
        )

        glassView = NSVisualEffectView(frame: glassFrame)
        glassView.material = .hudWindow
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = 10
        glassView.layer?.masksToBounds = true
        glassView.layer?.borderWidth = 0.5
        glassView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor

        textLayer = PasswordTextView(frame: NSRect(origin: .zero, size: frameRect.size))

        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false

        addSubview(glassView)

        textLayer.autoresizingMask = [.width, .height]
        textLayer.overlay = self
        addSubview(textLayer)

        startClock()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func startClock() {
        clockTimer?.invalidate()
        let showSeconds = UserDefaults.standard.bool(forKey: "ClockShowSeconds")
        let interval: TimeInterval = showSeconds ? 1.0 : 30.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.textLayer.needsDisplay = true }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    override func layout() {
        super.layout()
        let glassFrame = NSRect(
            x: bounds.midX - fieldW / 2,
            y: 22,
            width: fieldW,
            height: fieldH
        )
        glassView.frame = glassFrame
    }

    private func updateGlassBorder() {
        if isLockedOut {
            glassView.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.5).cgColor
            glassView.layer?.borderWidth = 1.0
        } else if isFocused {
            glassView.layer?.borderColor = NSColor(calibratedRed: 0.35, green: 0.68, blue: 1.0, alpha: 0.5).cgColor
            glassView.layer?.borderWidth = 1.0
        } else {
            glassView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
            glassView.layer?.borderWidth = 0.5
        }
    }
}

// MARK: - PasswordTextView

/// Draws clock, password text, and status on top of the glass view.
@MainActor
final class PasswordTextView: NSView {
    weak var overlay: OverlayView?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    private static let periodFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private let timeFormatter = DateFormatter()
    private var lastUse24Hour: Bool?
    private var lastShowSeconds: Bool?
    private var cachedBrandingText: String?
    private var cachedCustomMessage: String?
    private var cachedBrandingTextNeedsUpdate = true
    
    private var lastBatteryCheck = Date.distantPast
    private var cachedBattery: BatteryStatus?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    @objc private func defaultsChanged() {
        cachedBrandingTextNeedsUpdate = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let overlay else { return }
        let cx = bounds.midX
        let fieldY: CGFloat = 22

        // -- Clock Settings --
        let defaults = UserDefaults.standard
        let use24Hour = defaults.bool(forKey: "ClockUse24Hour")
        let showSeconds = defaults.bool(forKey: "ClockShowSeconds")
        // Default true for date if not registered yet
        defaults.register(defaults: ["ClockShowDate": true])
        let showDate = defaults.bool(forKey: "ClockShowDate")

        if lastUse24Hour != use24Hour || lastShowSeconds != showSeconds {
            lastUse24Hour = use24Hour
            lastShowSeconds = showSeconds
            if use24Hour {
                timeFormatter.dateFormat = showSeconds ? "H:mm:ss" : "H:mm"
            } else {
                timeFormatter.dateFormat = showSeconds ? "h:mm:ss" : "h:mm"
            }
        }

        let now = Date()
        let time = timeFormatter.string(from: now)
        let period = use24Hour ? "" : (" " + Self.periodFormatter.string(from: now))
        let date = Self.dateFormatter.string(from: now)

        // Build a single attributed string for time + period
        let timeFont = NSFont.systemFont(ofSize: 84, weight: .thin)
        let clockStr = NSMutableAttributedString(
            string: time,
            attributes: [.font: timeFont, .foregroundColor: NSColor.white]
        )
        
        if !use24Hour {
            let periodFont = NSFont.systemFont(ofSize: 24, weight: .light)
            clockStr.append(NSAttributedString(
                string: period,
                attributes: [.font: periodFont, .foregroundColor: NSColor(white: 0.6, alpha: 1.0)]
            ))
        }

        let clockSize = clockStr.size()
        let clockX = cx - clockSize.width / 2
        var clockY = bounds.midY + 20
        if !showDate {
            clockY -= 10 // Shift down slightly if no date to keep visual balance
        }
        clockStr.draw(at: CGPoint(x: clockX, y: clockY))

        // Date centered below
        if showDate {
            drawTextCentered(date, at: CGPoint(x: cx, y: clockY - 14), size: 20,
                             color: NSColor(white: 0.6, alpha: 1.0), weight: .regular)
        }
        
        // -- Widgets (Battery & Message) --
        // Check battery every 60 seconds
        if now.timeIntervalSince(lastBatteryCheck) > 60 {
            lastBatteryCheck = now
            cachedBattery = BatteryHelper.getStatus()
        }
        
        var widgetY = clockY - (showDate ? 40 : 25)
        
        if let batt = cachedBattery {
            let font = NSFont.systemFont(ofSize: 14, weight: .medium)
            let color = NSColor(white: 0.8, alpha: 1.0)
            let str = NSMutableAttributedString()
            
            let symbolName = batt.isCharging ? "battery.100.bolt" : (batt.percentage <= 20 ? "battery.25" : "battery.100")
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                if let tinted = image.withSymbolConfiguration(config) {
                    tinted.isTemplate = true
                    let attachment = NSTextAttachment()
                    attachment.image = tinted
                    attachment.bounds = CGRect(x: 0, y: -2, width: tinted.size.width, height: tinted.size.height)
                    
                    let imageStr = NSMutableAttributedString(attachment: attachment)
                    imageStr.addAttributes([.foregroundColor: color], range: NSRange(location: 0, length: imageStr.length))
                    str.append(imageStr)
                    str.append(NSAttributedString(string: " ", attributes: [.font: font]))
                }
            }
            
            str.append(NSAttributedString(string: "\(batt.percentage)%", attributes: [.font: font, .foregroundColor: color]))
            drawAttributedTextCentered(str, at: CGPoint(x: cx, y: widgetY))
            widgetY -= 22
        }
        
        if cachedBrandingTextNeedsUpdate {
            cachedBrandingText = defaults.string(forKey: "BrandingText") ?? "H0Ver"
            cachedCustomMessage = defaults.string(forKey: "CustomMessage")
            cachedBrandingTextNeedsUpdate = false
        }
        
        if let msg = cachedCustomMessage, !msg.isEmpty {
            drawTextCentered(msg, at: CGPoint(x: cx, y: widgetY), size: 14,
                             color: NSColor(white: 0.7, alpha: 1.0), weight: .medium)
        }

        // -- Branding only when no video --
        if !overlay.hasVideo {
            let text = cachedBrandingText ?? "H0Ver"
            drawTextCentered(text, at: CGPoint(x: cx, y: clockY + clockSize.height + 10), size: 16,
                             color: NSColor(white: 0.3, alpha: 1.0), weight: .medium)
        }

        // -- Password text inside the glass pill --
        if overlay.isLockedOut {
            drawTextCentered("Locked", at: CGPoint(x: cx, y: fieldY + 9), size: 14,
                             color: NSColor.systemRed.withAlphaComponent(0.8), weight: .medium)
        } else if overlay.passwordBuffer.isEmpty {
            drawTextCentered("Press Return for Touch ID", at: CGPoint(x: cx, y: fieldY + 9), size: 12,
                             color: NSColor(white: 0.55, alpha: 1.0), weight: .regular)
        } else {
            let bullets = String(repeating: "•", count: overlay.passwordBuffer.count)
            drawTextCentered(bullets, at: CGPoint(x: cx, y: fieldY + 7), size: 18,
                             color: .white, weight: .medium)
        }

        // -- Status --
        if !overlay.status.isEmpty {
            drawTextCentered(overlay.status, at: CGPoint(x: cx, y: fieldY + 36 + 10), size: 12,
                             color: overlay.statusColor, weight: .medium)
        }
    }

    private func drawTextCentered(_ text: String, at point: CGPoint, size: CGFloat,
                                  color: NSColor = .white, weight: NSFont.Weight = .regular) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        drawAttributedTextCentered(str, at: point)
    }

    private func drawAttributedTextCentered(_ str: NSAttributedString, at point: CGPoint) {
        let textWidth = str.size().width
        str.draw(at: CGPoint(x: point.x - textWidth / 2, y: point.y))
    }
}
