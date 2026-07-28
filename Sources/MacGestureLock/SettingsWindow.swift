import AppKit
import ServiceManagement

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

        let settingsView = SettingsView()
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = settingsView
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "H0Ver Settings"
        window.contentView = scrollView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        settingsView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            settingsView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            settingsView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor)
        ])

        self.window = window
    }
}

@MainActor
final class SettingsView: NSView {
    override var isFlipped: Bool { true } // Vital for top-to-bottom layout in NSScrollView

    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let videoPathField = NSTextField()
    private let browseButton = NSButton(title: "Browse...", target: nil, action: nil)
    
    private let oldPasswordField = NSSecureTextField()
    private let passwordField = NSSecureTextField()
    private let confirmPasswordField = NSSecureTextField()
    
    private let maxAttemptsField = NSTextField()
    private let maxAttemptsStepper = NSStepper()
    private let lockoutDurationPopup = NSPopUpButton()
    
    private let backgroundModePopup = NSPopUpButton()
    
    private let clock24HourCheckbox = NSButton(checkboxWithTitle: "Use 24-hour time format", target: nil, action: nil)
    private let clockSecondsCheckbox = NSButton(checkboxWithTitle: "Show seconds", target: nil, action: nil)
    private let clockDateCheckbox = NSButton(checkboxWithTitle: "Show date", target: nil, action: nil)
    private let showBatteryCheckbox = NSButton(checkboxWithTitle: "Show battery status", target: nil, action: nil)
    private let showWeatherCheckbox = NSButton(checkboxWithTitle: "Show weather widget", target: nil, action: nil)
    
    private let brandingField = NSTextField()
    private let customMessageField = NSTextField()
    
    private let checkUpdatesButton = NSButton(title: "Check for Updates...", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 20
        mainStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        mainStack.addArrangedSubview(makeSectionTitle("General"))
        
        let videoStack = NSStackView(views: [videoPathField, browseButton])
        videoStack.orientation = .horizontal
        videoStack.alignment = .firstBaseline
        videoPathField.usesSingleLineMode = true
        videoPathField.lineBreakMode = .byTruncatingHead
        videoPathField.placeholderString = "/path/to/video.mp4"
        videoPathField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        browseButton.target = self
        browseButton.action = #selector(browseVideo)
        
        backgroundModePopup.addItems(withTitles: ["Video File", "Liquid Gradient"])
        backgroundModePopup.widthAnchor.constraint(equalToConstant: 160).isActive = true
        
        let generalGrid = NSGridView(views: [
            [makeLabel("Startup"), launchAtLoginCheckbox],
            [makeLabel("Background"), backgroundModePopup],
            [makeLabel("Video Path"), videoStack]
        ])
        generalGrid.column(at: 0).xPlacement = .trailing
        generalGrid.rowAlignment = .firstBaseline
        mainStack.addArrangedSubview(generalGrid)
        
        makeDivider(for: mainStack)

        mainStack.addArrangedSubview(makeSectionTitle("Security"))
        
        oldPasswordField.placeholderString = "Required to save changes"
        passwordField.placeholderString = "Enter new password"
        confirmPasswordField.placeholderString = "Confirm password"
        
        let pWidth: CGFloat = 250
        oldPasswordField.widthAnchor.constraint(equalToConstant: pWidth).isActive = true
        passwordField.widthAnchor.constraint(equalToConstant: pWidth).isActive = true
        confirmPasswordField.widthAnchor.constraint(equalToConstant: pWidth).isActive = true

        let securityGrid = NSGridView(views: [
            [makeLabel("Old Password"), oldPasswordField],
            [makeLabel("New Password"), passwordField],
            [makeLabel("Confirm Password"), confirmPasswordField]
        ])
        securityGrid.column(at: 0).xPlacement = .trailing
        securityGrid.rowAlignment = .firstBaseline
        mainStack.addArrangedSubview(securityGrid)
        
        makeDivider(for: mainStack)

        mainStack.addArrangedSubview(makeSectionTitle("Lockout"))
        
        maxAttemptsField.isEditable = false
        maxAttemptsField.alignment = .center
        maxAttemptsField.widthAnchor.constraint(equalToConstant: 40).isActive = true
        
        maxAttemptsStepper.minValue = 3
        maxAttemptsStepper.maxValue = 10
        maxAttemptsStepper.increment = 1
        maxAttemptsStepper.target = self
        maxAttemptsStepper.action = #selector(stepperChanged)
        
        let attemptsStack = NSStackView(views: [maxAttemptsField, maxAttemptsStepper])
        attemptsStack.orientation = .horizontal
        
        lockoutDurationPopup.addItems(withTitles: ["10 seconds", "30 seconds", "60 seconds", "120 seconds"])
        lockoutDurationPopup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        
        let lockoutGrid = NSGridView(views: [
            [makeLabel("Max Attempts"), attemptsStack],
            [makeLabel("Cooldown"), lockoutDurationPopup]
        ])
        lockoutGrid.column(at: 0).xPlacement = .trailing
        lockoutGrid.rowAlignment = .firstBaseline
        mainStack.addArrangedSubview(lockoutGrid)
        
        makeDivider(for: mainStack)

        mainStack.addArrangedSubview(makeSectionTitle("Clock & Appearance"))
        
        let clockStack = NSStackView(views: [clock24HourCheckbox, clockSecondsCheckbox, clockDateCheckbox, showBatteryCheckbox, showWeatherCheckbox])
        clockStack.orientation = .vertical
        clockStack.alignment = .leading
        
        brandingField.placeholderString = "H0Ver"
        brandingField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        
        customMessageField.placeholderString = "Optional widget text (e.g. Back in 5 mins)"
        customMessageField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        
        let appearanceGrid = NSGridView(views: [
            [makeLabel("Clock Display"), clockStack],
            [makeLabel("Fallback Text"), brandingField],
            [makeLabel("Custom Widget"), customMessageField]
        ])
        appearanceGrid.column(at: 0).xPlacement = .trailing
        appearanceGrid.rowAlignment = .firstBaseline
        mainStack.addArrangedSubview(appearanceGrid)
        
        makeDivider(for: mainStack)
        
        let footerStack = NSStackView()
        footerStack.orientation = .horizontal
        
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        checkUpdatesButton.bezelStyle = .rounded
        checkUpdatesButton.target = self
        checkUpdatesButton.action = #selector(checkForUpdates)
        
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(save)
        
        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let versionLabel = NSTextField(labelWithString: "v\(versionString)")
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let leftFooterStack = NSStackView(views: [checkUpdatesButton, versionLabel, statusLabel])
        leftFooterStack.orientation = .horizontal
        leftFooterStack.spacing = 10
        leftFooterStack.alignment = .firstBaseline
        
        footerStack.addView(leftFooterStack, in: .leading)
        footerStack.addView(saveButton, in: .trailing)
        
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(footerStack)
        footerStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -48).isActive = true
    }
    
    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        return label
    }
    
    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }
    
    @discardableResult
    private func makeDivider(for stack: NSStackView) -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        return box
    }

    @objc private func stepperChanged() {
        maxAttemptsField.stringValue = "\(maxAttemptsStepper.integerValue)"
    }
    
    @objc private func checkForUpdates() {
        UpdateChecker.check(manual: true)
    }
    
    @objc private func browseVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        if panel.runModal() == .OK, let url = panel.url {
            videoPathField.stringValue = url.path
        }
    }
    
    private func loadSettings() {
        if #available(macOS 13.0, *) {
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginCheckbox.isHidden = true
        }

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
        
        defaults.register(defaults: [
            "ClockShowDate": true,
            "BrandingText": "H0Ver",
            "BackgroundMode": 0
        ])
        
        let mode = defaults.integer(forKey: "BackgroundMode")
        backgroundModePopup.selectItem(at: (mode >= 0 && mode < 2) ? mode : 0)
        
        clockDateCheckbox.state = defaults.bool(forKey: "ClockShowDate") ? .on : .off
        showBatteryCheckbox.state = defaults.bool(forKey: "ShowBattery") ? .on : .off
        showWeatherCheckbox.state = defaults.bool(forKey: "ShowWeather") ? .on : .off
        brandingField.stringValue = defaults.string(forKey: "BrandingText") ?? "H0Ver"
        customMessageField.stringValue = defaults.string(forKey: "CustomMessage") ?? ""
    }

    @objc private func save() {
        statusLabel.textColor = .systemRed

        if #available(macOS 13.0, *) {
            do {
                if launchAtLoginCheckbox.state == .on {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                statusLabel.stringValue = "Failed to set login item."
                return
            }
        }

        let defaults = UserDefaults.standard
        let currentPassword = defaults.string(forKey: "AppPassword")
        
        if let current = currentPassword, !current.isEmpty {
            if oldPasswordField.stringValue != current {
                statusLabel.stringValue = "Incorrect old password."
                return
            }
        }

        let newPass = passwordField.stringValue
        let confirmPass = confirmPasswordField.stringValue

        if !newPass.isEmpty || !confirmPass.isEmpty {
            if newPass != confirmPass {
                statusLabel.stringValue = "New passwords do not match."
                return
            }
            defaults.set(newPass, forKey: "AppPassword")
        }
        
        let path = videoPathField.stringValue.trimmingCharacters(in: .whitespaces)
        if path.isEmpty {
            defaults.removeObject(forKey: "ScreensaverVideo")
        } else {
            defaults.set(path, forKey: "ScreensaverVideo")
        }

        defaults.set(backgroundModePopup.indexOfSelectedItem, forKey: "BackgroundMode")

        let durations = [10, 30, 60, 120]
        let idx = lockoutDurationPopup.indexOfSelectedItem
        if idx >= 0 && idx < durations.count {
            defaults.set(durations[idx], forKey: "LockoutDuration")
        }

        defaults.set(maxAttemptsStepper.integerValue, forKey: "MaxAttempts")
        defaults.set(clock24HourCheckbox.state == .on, forKey: "ClockUse24Hour")
        defaults.set(clockSecondsCheckbox.state == .on, forKey: "ClockShowSeconds")
        defaults.set(clockDateCheckbox.state == .on, forKey: "ClockShowDate")
        defaults.set(showBatteryCheckbox.state == .on, forKey: "ShowBattery")
        defaults.set(showWeatherCheckbox.state == .on, forKey: "ShowWeather")
        
        let text = brandingField.stringValue.trimmingCharacters(in: .whitespaces)
        defaults.set(text.isEmpty ? "H0Ver" : text, forKey: "BrandingText")
        
        let msg = customMessageField.stringValue.trimmingCharacters(in: .whitespaces)
        if msg.isEmpty {
            defaults.removeObject(forKey: "CustomMessage")
        } else {
            defaults.set(msg, forKey: "CustomMessage")
        }

        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = "Settings saved successfully!"
        
        oldPasswordField.stringValue = ""
        passwordField.stringValue = ""
        confirmPasswordField.stringValue = ""
    }
}
