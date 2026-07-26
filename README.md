# H0Ver — Mac Screen Lock

A premium macOS utility that overlays a full-screen video or an animated liquid gradient screensaver, unlockable via an in-app password or native Touch ID. The lock screen features a beautiful frosted-glass (liquid glass) password field, a live clock, and native lock screen widgets.

## Features ✨

- **Beautiful Backgrounds**: Choose between a custom looping video (`.mp4`, `.mov`) or a buttery smooth "Liquid Gradient" (powered by CoreAnimation).
- **Global Hotkey**: Press **`Cmd + Option + L`** from *anywhere* on your Mac to instantly lock your screen.
- **Lock Screen Widgets**: Displays a live Battery percentage using native SF Symbols, plus an optional Custom Message right below the clock.
- **Touch ID Integration**: Press **Return** when the password field is empty to instantly invoke macOS Touch ID to unlock.
- **Launch at Login**: Automatically start H0Ver securely in the background when you boot your Mac.
- **Keychain Security**: Your custom app password is encrypted and securely stored in the native macOS Keychain.
- **Smart Cooldown**: Temporarily locks out intruders with an expanding cooldown timer after consecutive failed attempts.

## Security Limitation

This is an app-level overlay, **not** a replacement for macOS LoginWindow, FileVault, or the system lock screen. A privileged user or someone with physical access may still bypass or quit the app. Keep normal macOS security enabled.

## Build and Install

To build the app bundle, use the provided script:

```bash
./bundle.sh
```

This will compile a release binary and package it into `H0Ver.app`.

You can run the app directly or copy it to your Applications folder:

```bash
open H0Ver.app
# OR
cp -r H0Ver.app /Applications/
```

## How It Works

Once launched, H0Ver lives in your menu bar (as a menu bar extra). It does not appear in your Dock.

- **Fastest way to lock:** Press **`Cmd + Option + L`**.
- **Menu bar lock:** Click the `H0Ver` menu bar item and select **Lock Now** (or press `L` when the menu is open).
- When unlocked, the lock screen disappears but the app stays running silently in the background.

## Configuration

Select **Settings...** from the menu bar to customize the app. H0Ver features a native, auto-layout Mac UI for flawless configuration.

You can configure:
- **Startup:** Toggle *Launch at Login*.
- **Background:** Choose between `Video File` or `Liquid Gradient`.
- **Clock Display:** Toggle 24-hour time, seconds, and date visibility.
- **Custom Widget:** Type a message (e.g. "At Lunch") to display on the lock screen.
- **Security:** Change your unlock password (requires entering your old password first to verify it's you).
- **Lockout Options:** Configure the max failed attempts and the cooldown duration.

## Unlocking

Type your password directly and press **Return**. No need to click the field.

| Action | Shortcut |
|---|---|
| Submit password | Return |
| **Trigger Touch ID** | **Return** (when field is empty) or **Fn+T** |
| Backspace | Delete last character |
| Emergency quit (testing) | Esc ×5 or Cmd+Q |

- Clicks, drags, swipes, and gestures are disabled while locked.
- The password field has a frosted-glass blur effect over the video.
- One overlay window per display, kept frontmost at screen-saver level.
- Multi-monitor support is best-effort.
