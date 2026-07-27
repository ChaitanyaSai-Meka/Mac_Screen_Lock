import AppKit
import AVKit
import LocalAuthentication
struct Config {
    let videoPath: String?
    let appPassword: String
    let maxAttempts: Int
    let lockoutBaseDuration: Int

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
    private var authContext: LAContext?
    private var keepFrontTimer: Timer?
    private var eventMonitors: [Any] = []

    private var failedAttempts = 0
    private var lockedOut = false
    private var lockoutTimer: Timer?
    private var maxAttempts: Int { config.maxAttempts }
    private var lockoutDuration: TimeInterval {
        Double(config.lockoutBaseDuration) * Double(max(min(failedAttempts - maxAttempts + 1, 6), 1))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "ClockShowDate": true,
            "BrandingText": "H0Ver",
            "BackgroundMode": 0
        ])
        NSApplication.shared.setActivationPolicy(.accessory)
        makeMenuBarItem()
        installEventMonitors()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        BatteryHelper.startMonitoring()
        NotificationCenter.default.addObserver(self, selector: #selector(batteryStatusChanged), name: NSNotification.Name("BatteryStatusChanged"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reassertOverlay), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        GlobalHotkeyManager.shared.register()
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
    @objc private func batteryStatusChanged() {
        windows.compactMap { $0.contentView as? LockView }.forEach { $0.forceBatteryUpdate() }
    }

    private func lock() {
        config = Config.load()
        authenticationInProgress = false
        applyLockedPresentationOptions()
        windows.forEach { ($0.contentView as? LockView)?.cleanup(); $0.close() }
        windows = NSScreen.screens.map(makeWindow)
        
        if lockedOut {
            windows.compactMap { $0.contentView as? LockView }.forEach { $0.setLockedOut(true) }
            setStatus("Too many attempts \u{2014} wait \(lockoutRemaining)s", color: NSColor.systemRed)
        }
        
        startKeepFrontTimer()
        NSApplication.shared.activate(ignoringOtherApps: true)
        reassertFirstResponder()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let mode = UserDefaults.standard.integer(forKey: "BackgroundMode")
        let isPrimary = screen == NSScreen.main
        let view = LockView(frame: screen.frame, videoURL: videoURL(), backgroundMode: mode, isPrimary: isPrimary)
        view.onAuthenticate = { [weak self] in self?.authenticateWithTouchID() }
        view.onCancelTouchID = { [weak self] in self?.cancelTouchID() }
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
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reassertOverlay() }
        }
        RunLoop.main.add(timer, forMode: .common)
        keepFrontTimer = timer
    }
    
    @objc private func reassertOverlay() {
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
        authContext = context
        context.localizedCancelTitle = "Stay Locked"
        context.localizedFallbackTitle = "Enter Mac Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationInProgress = false
            authContext = nil
            setStatus("Biometrics unavailable", color: NSColor.systemRed)
            reassertFirstResponder()
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock H0Ver screen") { [weak self] success, authError in
            DispatchQueue.main.async {
                guard let self else { return }
                // If authentication is no longer in progress, it was cancelled by typing
                guard self.authenticationInProgress else { return }
                
                self.authenticationInProgress = false
                self.authContext = nil
                
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
    
    private func cancelTouchID() {
        if authenticationInProgress {
            authContext?.invalidate()
            authContext = nil
            authenticationInProgress = false
            setStatus("", color: .white)
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
            Task { @MainActor in
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
        
        let unlockingWindows = self.windows
        self.windows = []

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            for window in unlockingWindows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                
                unlockingWindows.forEach { ($0.contentView as? LockView)?.cleanup(); $0.close() }
                
                // Only restore presentation options if we haven't locked again
                if self.windows.isEmpty {
                    self.keepFrontTimer?.invalidate()
                    self.keepFrontTimer = nil
                    self.restorePresentationOptions()
                }
            }
        })
    }
}
@MainActor
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@MainActor
final class LockView: NSView {
    var onAuthenticate: (() -> Void)?
    var onCancelTouchID: (() -> Void)?
    var onPasswordSubmit: ((String) -> Void)?
    var onEmergencyQuit: (() -> Void)?
    var isLockedOut: (() -> Bool)?

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var hasVideo = false
    private let overlayView: OverlayView

    init(frame frameRect: NSRect, videoURL: URL?, backgroundMode: Int = 0, isPrimary: Bool = true) {
        overlayView = OverlayView(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        wantsLayer = true

        if backgroundMode == 1 {
            let gradientView = AnimatedGradientView(frame: bounds)
            gradientView.autoresizingMask = [.width, .height]
            addSubview(gradientView)
            self.hasVideo = true
        } else if let videoURL {
            let item = AVPlayerItem(url: videoURL)
            let queuePlayer = AVQueuePlayer(playerItem: item)
            queuePlayer.isMuted = !isPrimary
            
            let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            
            let layer = AVPlayerLayer(player: queuePlayer)
            layer.videoGravity = .resizeAspectFill
            self.layer?.addSublayer(layer)
            self.player = queuePlayer
            self.looper = looper
            self.playerLayer = layer
            self.hasVideo = true
            queuePlayer.play()
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
    
    func forceBatteryUpdate() {
        overlayView.forceBatteryUpdate()
    }

    override func keyDown(with event: NSEvent) {
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
            onCancelTouchID?()
            overlayView.escapeCount += 1
            setStatus("Emergency quit: Esc x\(max(0, 5 - overlayView.escapeCount)) more", color: NSColor.systemOrange)
            if overlayView.escapeCount >= 5 { onEmergencyQuit?() }
        } else if let chars = event.characters, !chars.isEmpty,
                  !modifiers.contains(.command), !modifiers.contains(.control) {
            onCancelTouchID?()
            overlayView.escapeCount = 0
            if overlayView.passwordBuffer.count < 128 {
                overlayView.passwordBuffer.append(contentsOf: chars)
            }
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
@MainActor
final class OverlayView: NSView {
    var status = "" { didSet { textLayer.updateUI() } }
    var statusColor = NSColor.white { didSet { textLayer.updateUI() } }
    var passwordBuffer = "" { didSet { textLayer.updateUI() } }
    var escapeCount = 0
    var isFocused = false { didSet { updateGlassBorder(); textLayer.updateUI() } }
    var isLockedOut = false { didSet { updateGlassBorder(); textLayer.updateUI() } }
    var hasVideo = false { didSet { textLayer.updateUI() } }

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
            Task { @MainActor in self?.textLayer.updateUI() }
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

    func forceBatteryUpdate() {
        textLayer.forceBatteryUpdate()
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
@MainActor
final class PasswordTextView: NSView {
    weak var overlay: OverlayView?

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
    private let timeFont = NSFont.systemFont(ofSize: 84, weight: .thin)
    private let periodFont = NSFont.systemFont(ofSize: 24, weight: .light)
    private let dateFont = NSFont.systemFont(ofSize: 20, weight: .regular)
    private let batteryFont = NSFont.systemFont(ofSize: 14, weight: .medium)
    
    private let timeLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let batteryLabel = NSTextField(labelWithString: "")
    private let customMessageLabel = NSTextField(labelWithString: "")
    private let brandingLabel = NSTextField(labelWithString: "")
    private let passwordLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        
        let labels = [timeLabel, dateLabel, batteryLabel, customMessageLabel, brandingLabel, passwordLabel, statusLabel]
        for label in labels {
            label.alignment = .center
            label.drawsBackground = false
            label.isBordered = false
            label.isEditable = false
            label.isSelectable = false
            addSubview(label)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func forceBatteryUpdate() {
        lastBatteryCheck = Date.distantPast
        updateUI()
    }
    
    @objc private func defaultsChanged() {
        cachedBrandingTextNeedsUpdate = true
    }
    
    func updateUI() {
        guard let overlay else { return }

        let defaults = UserDefaults.standard
        let use24Hour = defaults.bool(forKey: "ClockUse24Hour")
        let showSeconds = defaults.bool(forKey: "ClockShowSeconds")
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

        let clockStr = NSMutableAttributedString(
            string: time,
            attributes: [.font: timeFont, .foregroundColor: NSColor.white]
        )
        
        if !use24Hour {
            clockStr.append(NSAttributedString(
                string: period,
                attributes: [.font: periodFont, .foregroundColor: NSColor(white: 0.6, alpha: 1.0)]
            ))
        }
        timeLabel.attributedStringValue = clockStr

        if showDate {
            dateLabel.font = dateFont
            dateLabel.textColor = NSColor(white: 0.6, alpha: 1.0)
            dateLabel.stringValue = date
            dateLabel.isHidden = false
        } else {
            dateLabel.isHidden = true
        }
        
        if now.timeIntervalSince(lastBatteryCheck) > 60 || cachedBattery == nil {
            lastBatteryCheck = now
            cachedBattery = BatteryHelper.getStatus()
            
            if let batt = cachedBattery {
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
                        str.append(NSAttributedString(string: " ", attributes: [.font: batteryFont]))
                    }
                }
                
                str.append(NSAttributedString(string: "\(batt.percentage)%", attributes: [.font: batteryFont, .foregroundColor: color]))
                batteryLabel.attributedStringValue = str
                batteryLabel.isHidden = false
            } else {
                batteryLabel.isHidden = true
            }
        }
        
        if cachedBrandingTextNeedsUpdate {
            cachedBrandingText = defaults.string(forKey: "BrandingText") ?? "H0Ver"
            cachedCustomMessage = defaults.string(forKey: "CustomMessage")
            cachedBrandingTextNeedsUpdate = false
        }
        
        if let msg = cachedCustomMessage, !msg.isEmpty {
            customMessageLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            customMessageLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
            customMessageLabel.stringValue = msg
            customMessageLabel.isHidden = false
        } else {
            customMessageLabel.isHidden = true
        }

        if !overlay.hasVideo {
            let text = cachedBrandingText ?? "H0Ver"
            brandingLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
            brandingLabel.textColor = NSColor(white: 0.3, alpha: 1.0)
            brandingLabel.stringValue = text
            brandingLabel.isHidden = false
        } else {
            brandingLabel.isHidden = true
        }

        passwordLabel.font = NSFont.systemFont(ofSize: overlay.passwordBuffer.isEmpty ? 12 : 18, weight: overlay.passwordBuffer.isEmpty ? .regular : .medium)
        if overlay.isLockedOut {
            passwordLabel.textColor = NSColor.systemRed.withAlphaComponent(0.8)
            passwordLabel.stringValue = "Locked"
        } else if overlay.passwordBuffer.isEmpty {
            passwordLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
            passwordLabel.stringValue = "Press Return for Touch ID"
        } else {
            passwordLabel.textColor = .white
            passwordLabel.stringValue = String(repeating: "•", count: overlay.passwordBuffer.count)
        }

        if !overlay.status.isEmpty {
            statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            statusLabel.textColor = overlay.statusColor
            statusLabel.stringValue = overlay.status
            statusLabel.isHidden = false
        } else {
            statusLabel.isHidden = true
        }
        
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let cx = bounds.midX
        let fieldY: CGFloat = 22
        
        timeLabel.sizeToFit()
        var clockY = bounds.midY + 20
        if dateLabel.isHidden { clockY -= 10 }
        timeLabel.frame = NSRect(x: cx - timeLabel.bounds.width / 2, y: clockY, width: timeLabel.bounds.width, height: timeLabel.bounds.height)
        
        if !dateLabel.isHidden {
            dateLabel.sizeToFit()
            dateLabel.frame = NSRect(x: cx - dateLabel.bounds.width / 2, y: clockY - 14, width: dateLabel.bounds.width, height: dateLabel.bounds.height)
        }
        
        var widgetY = clockY - (!dateLabel.isHidden ? 40 : 25)
        
        if !batteryLabel.isHidden {
            batteryLabel.sizeToFit()
            batteryLabel.frame = NSRect(x: cx - batteryLabel.bounds.width / 2, y: widgetY, width: batteryLabel.bounds.width, height: batteryLabel.bounds.height)
            widgetY -= 22
        }
        
        if !customMessageLabel.isHidden {
            customMessageLabel.sizeToFit()
            customMessageLabel.frame = NSRect(x: cx - customMessageLabel.bounds.width / 2, y: widgetY, width: customMessageLabel.bounds.width, height: customMessageLabel.bounds.height)
        }
        
        if !brandingLabel.isHidden {
            brandingLabel.sizeToFit()
            brandingLabel.frame = NSRect(x: cx - brandingLabel.bounds.width / 2, y: clockY + timeLabel.bounds.height + 10, width: brandingLabel.bounds.width, height: brandingLabel.bounds.height)
        }
        
        passwordLabel.sizeToFit()
        let pwdY = fieldY + ((overlay?.isLockedOut ?? false) ? 9 : ((overlay?.passwordBuffer.isEmpty ?? true) ? 9 : 7))
        passwordLabel.frame = NSRect(x: cx - passwordLabel.bounds.width / 2, y: pwdY, width: passwordLabel.bounds.width, height: passwordLabel.bounds.height)
        
        if !statusLabel.isHidden {
            statusLabel.sizeToFit()
            statusLabel.frame = NSRect(x: cx - statusLabel.bounds.width / 2, y: fieldY + 36 + 10, width: statusLabel.bounds.width, height: statusLabel.bounds.height)
        }
    }
}
