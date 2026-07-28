# H0Ver — Mac Screen Lock

A premium macOS utility that overlays a full-screen video or an animated liquid gradient screensaver, unlockable via an in-app password or native Touch ID. The lock screen features a beautiful frosted-glass (liquid glass) password field, a live clock, and native lock screen widgets.

## Features

- **Beautiful Backgrounds**: Choose between a custom looping video (`.mp4`, `.mov`) or a buttery smooth "Liquid Gradient" (powered by CoreAnimation).
- **Global Hotkey**: Press **`Cmd + Shift + L`** from *anywhere* on your Mac to instantly lock your screen.
- **Lock Screen Widgets**: Displays live widgets including Battery percentage, Weather condition with accurate temperature (powered by CoreLocation and Open-Meteo), and currently playing Media (Apple Music/Spotify).
- **Custom Widget**: Display an optional Custom Message right below the clock.
- **Touch ID Integration**: Press **Return** when the password field is empty to instantly invoke macOS Touch ID to unlock. If Touch ID fails or is unavailable, it gracefully falls back to your Mac user password.
- **Launch at Login**: Automatically start H0Ver securely in the background when you boot your Mac.
- **Updates**: Manually check the official GitHub repository for new versions via Settings.
- **Smart Cooldown**: Temporarily locks out intruders with an expanding cooldown timer after consecutive failed attempts.

## Security Limitation

**CRITICAL**: This is an app-level overlay, **not** a replacement for macOS LoginWindow, FileVault, or the system lock screen. Because it is an application running in user-space, it cannot provide the deep OS-level guarantees of the real macOS lock screen. A privileged user or someone with physical access may still bypass or force-quit the app under certain conditions. Keep normal macOS security and screen sleep passwords enabled.

## Installation (Direct Download)

If you downloaded the pre-compiled `H0Ver.app.zip`:

1. Extract the `.zip` file.
2. Open your terminal and remove the macOS quarantine attribute by running:
   ```bash
   xattr -r -c /path/to/H0Ver.app
   ```
3. Drag `H0Ver.app` into your `/Applications/` folder.
4. Launch the app!

## Build from Source

To build the app bundle from source, use the provided script:

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

- **Fastest way to lock:** Press **`Cmd + Shift + L`**.
- **Menu bar lock:** Click the `H0Ver` menu bar item and select **Lock Now** (or press `Cmd + Shift + L`).
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
- **Updates:** Click *Check for Updates...* to download the latest release from GitHub.

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
