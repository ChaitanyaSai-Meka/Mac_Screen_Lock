import AppKit

// MARK: - SettingsWindowController

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView(frame: NSRect(x: 0, y: 0, width: 480, height: 540))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "H0Ver Settings"
        window.contentView = contentView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

// MARK: - SettingsView

@MainActor
final class SettingsView: NSView {
    private let videoPathField = NSTextField()
    private let browseButton = NSButton(title: "Browse...", target: nil, action: nil)
    private let passwordField = NSSecureTextField()
    private let confirmPasswordField = NSSecureTextField()
    private let maxAttemptsField = NSTextField()
    private let maxAttemptsStepper = NSStepper()
    private let lockoutDurationPopup = NSPopUpButton()

    private let clock24HourCheckbox = NSButton(checkboxWithTitle: "Use 24-hour time format", target: nil, action: nil)
    private let clockSecondsCheckbox = NSButton(checkboxWithTitle: "Show seconds", target: nil, action: nil)
    private let clockDateCheckbox = NSButton(checkboxWithTitle: "Show date", target: nil, action: nil)

    private let brandingField = NSTextField()

    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        let padding: CGFloat = 24
        let labelW: CGFloat = 130
        let fieldX: CGFloat = padding + labelW + 8
        let fieldW: CGFloat = bounds.width - fieldX - padding
        var y: CGFloat = bounds.height - 50

        // ── Title ──
        let title = NSTextField(labelWithString: "H0Ver Settings")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.frame = NSRect(x: padding, y: y, width: 200, height: 24)
        addSubview(title)

        y -= 14
        let divider1 = makeDivider(y: y, width: bounds.width - 2 * padding, x: padding)
        addSubview(divider1)

        // ── Video Path ──
        y -= 36
        addSubview(makeLabel("Video Path", at: NSPoint(x: padding, y: y + 2)))

        videoPathField.frame = NSRect(x: fieldX, y: y, width: fieldW - 90, height: 24)
        videoPathField.placeholderString = "/path/to/video.mp4"
        videoPathField.font = NSFont.systemFont(ofSize: 13)
        videoPathField.lineBreakMode = .byTruncatingMiddle
        addSubview(videoPathField)

        browseButton.frame = NSRect(x: bounds.width - padding - 82, y: y - 1, width: 82, height: 26)
        browseButton.bezelStyle = .rounded
        browseButton.font = NSFont.systemFont(ofSize: 12)
        browseButton.target = self
        browseButton.action = #selector(browseVideo)
        addSubview(browseButton)

        // ── Password ──
        y -= 40
        addSubview(makeLabel("New Password", at: NSPoint(x: padding, y: y + 2)))

        passwordField.frame = NSRect(x: fieldX, y: y, width: fieldW, height: 24)
        passwordField.placeholderString = "Enter new password"
        passwordField.font = NSFont.systemFont(ofSize: 13)
        addSubview(passwordField)

        y -= 32
        addSubview(makeLabel("Confirm Password", at: NSPoint(x: padding, y: y + 2)))

        confirmPasswordField.frame = NSRect(x: fieldX, y: y, width: fieldW, height: 24)
        confirmPasswordField.placeholderString = "Confirm password"
        confirmPasswordField.font = NSFont.systemFont(ofSize: 13)
        addSubview(confirmPasswordField)

        // ── Lockout Settings ──
        y -= 44
        let divider2 = makeDivider(y: y + 16, width: bounds.width - 2 * padding, x: padding)
        addSubview(divider2)

        let lockoutTitle = NSTextField(labelWithString: "Lockout")
        lockoutTitle.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        lockoutTitle.frame = NSRect(x: padding, y: y - 4, width: 200, height: 20)
        addSubview(lockoutTitle)

        y -= 36
        addSubview(makeLabel("Max Attempts", at: NSPoint(x: padding, y: y + 2)))

        maxAttemptsField.frame = NSRect(x: fieldX, y: y, width: 50, height: 24)
        maxAttemptsField.font = NSFont.systemFont(ofSize: 13)
        maxAttemptsField.alignment = .center
        maxAttemptsField.isEditable = false
        addSubview(maxAttemptsField)

        maxAttemptsStepper.frame = NSRect(x: fieldX + 54, y: y - 1, width: 19, height: 26)
        maxAttemptsStepper.minValue = 3
        maxAttemptsStepper.maxValue = 10
        maxAttemptsStepper.increment = 1
        maxAttemptsStepper.target = self
        maxAttemptsStepper.action = #selector(stepperChanged)
        addSubview(maxAttemptsStepper)

        y -= 32
        addSubview(makeLabel("Cooldown Duration", at: NSPoint(x: padding, y: y + 2)))

        lockoutDurationPopup.frame = NSRect(x: fieldX, y: y - 2, width: 140, height: 28)
        lockoutDurationPopup.addItems(withTitles: ["10 seconds", "30 seconds", "60 seconds", "120 seconds"])
        lockoutDurationPopup.font = NSFont.systemFont(ofSize: 13)
        addSubview(lockoutDurationPopup)

        // ── Clock Settings ──
        y -= 44
        let divider3 = makeDivider(y: y + 16, width: bounds.width - 2 * padding, x: padding)
        addSubview(divider3)

        let clockTitle = NSTextField(labelWithString: "Clock Display")
        clockTitle.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        clockTitle.frame = NSRect(x: padding, y: y - 4, width: 200, height: 20)
        addSubview(clockTitle)

        y -= 30
        clock24HourCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldW, height: 20)
        clock24HourCheckbox.font = NSFont.systemFont(ofSize: 13)
        addSubview(clock24HourCheckbox)

        y -= 26
        clockSecondsCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldW, height: 20)
        clockSecondsCheckbox.font = NSFont.systemFont(ofSize: 13)
        addSubview(clockSecondsCheckbox)

        y -= 26
        clockDateCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldW, height: 20)
        clockDateCheckbox.font = NSFont.systemFont(ofSize: 13)
        addSubview(clockDateCheckbox)

        // ── Branding ──
        y -= 44
        let divider4 = makeDivider(y: y + 16, width: bounds.width - 2 * padding, x: padding)
        addSubview(divider4)

        let brandingTitle = NSTextField(labelWithString: "Appearance")
        brandingTitle.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        brandingTitle.frame = NSRect(x: padding, y: y - 4, width: 200, height: 20)
        addSubview(brandingTitle)

        y -= 36
        addSubview(makeLabel("Fallback Text", at: NSPoint(x: padding, y: y + 2)))

        brandingField.frame = NSRect(x: fieldX, y: y, width: fieldW, height: 24)
        brandingField.placeholderString = "H0Ver"
        brandingField.font = NSFont.systemFont(ofSize: 13)
        addSubview(brandingField)

        // ── Save Button ──
        y -= 50
        let divider5 = makeDivider(y: y + 20, width: bounds.width - 2 * padding, x: padding)
        addSubview(divider5)

        saveButton.frame = NSRect(x: bounds.width - padding - 80, y: y - 6, width: 80, height: 30)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        saveButton.target = self
        saveButton.action = #selector(save)
        addSubview(saveButton)

        statusLabel.frame = NSRect(x: padding, y: y - 2, width: bounds.width - padding * 2 - 90, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        addSubview(statusLabel)
    }

    // MARK: - Load/Save

    private func loadSettings() {
        let defaults = UserDefaults.standard
        videoPathField.stringValue = defaults.string(forKey: "ScreensaverVideo") ?? ""

        let attempts = defaults.integer(forKey: "MaxAttempts")
        let maxAttempts = attempts > 0 ? attempts : 5
        maxAttemptsField.stringValue = "\(maxAttempts)"
        maxAttemptsStepper.integerValue = maxAttempts

        let duration = defaults.integer(forKey: "LockoutDuration")
        switch duration {
        case 30: lockoutDurationPopup.selectItem(at: 1)
        case 60: lockoutDurationPopup.selectItem(at: 2)
        case 120: lockoutDurationPopup.selectItem(at: 3)
        default: lockoutDurationPopup.selectItem(at: 0)
        }

        clock24HourCheckbox.state = defaults.bool(forKey: "ClockUse24Hour") ? .on : .off
        clockSecondsCheckbox.state = defaults.bool(forKey: "ClockShowSeconds") ? .on : .off
        
        // Defaults to true for date if not set, check by registering default
        defaults.register(defaults: [
            "ClockShowDate": true,
            "BrandingText": "H0Ver"
        ])
        clockDateCheckbox.state = defaults.bool(forKey: "ClockShowDate") ? .on : .off

        brandingField.stringValue = defaults.string(forKey: "BrandingText") ?? "H0Ver"
    }

    @objc private func save() {
        let defaults = UserDefaults.standard

        // Video path
        let path = videoPathField.stringValue.trimmingCharacters(in: .whitespaces)
        if path.isEmpty {
            defaults.removeObject(forKey: "ScreensaverVideo")
        } else {
            defaults.set(path, forKey: "ScreensaverVideo")
        }

        // Password
        let pw = passwordField.stringValue
        let confirm = confirmPasswordField.stringValue
        if !pw.isEmpty {
            if pw != confirm {
                statusLabel.stringValue = "Passwords do not match."
                statusLabel.textColor = .systemRed
                return
            }
            defaults.set(pw, forKey: "AppPassword")
        }

        // Lockout
        defaults.set(maxAttemptsStepper.integerValue, forKey: "MaxAttempts")

        let durations = [10, 30, 60, 120]
        let idx = lockoutDurationPopup.indexOfSelectedItem
        defaults.set(durations[idx], forKey: "LockoutDuration")

        // Clock
        defaults.set(clock24HourCheckbox.state == .on, forKey: "ClockUse24Hour")
        defaults.set(clockSecondsCheckbox.state == .on, forKey: "ClockShowSeconds")
        defaults.set(clockDateCheckbox.state == .on, forKey: "ClockShowDate")

        // Branding
        let branding = brandingField.stringValue.trimmingCharacters(in: .whitespaces)
        defaults.set(branding.isEmpty ? "H0Ver" : branding, forKey: "BrandingText")

        // Clear password fields
        passwordField.stringValue = ""
        confirmPasswordField.stringValue = ""

        statusLabel.stringValue = "Settings saved."
        statusLabel.textColor = .systemGreen

        // Clear after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.statusLabel.stringValue = ""
        }
    }

    // MARK: - Actions

    @objc private func browseVideo() {
        let panel = NSOpenPanel()
        panel.title = "Choose a video file"
        panel.allowedContentTypes = [
            .movie, .mpeg4Movie, .quickTimeMovie
        ]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.level = .modalPanel

        if panel.runModal() == .OK, let url = panel.url {
            videoPathField.stringValue = url.path
        }
    }

    @objc private func stepperChanged() {
        maxAttemptsField.stringValue = "\(maxAttemptsStepper.integerValue)"
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, at origin: NSPoint) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: origin.x, y: origin.y, width: 130, height: 20)
        label.alignment = .right
        return label
    }

    private func makeDivider(y: CGFloat, width: CGFloat, x: CGFloat) -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.frame = NSRect(x: x, y: y, width: width, height: 1)
        return box
    }
}
