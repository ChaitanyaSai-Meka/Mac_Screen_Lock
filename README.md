# H0Ver — Mac Screen Lock

A macOS app that overlays a full-screen video screensaver with audio, unlockable via an in-app password or Touch ID. The password field uses a native frosted-glass (liquid glass) effect.

If no video is configured, the app displays a black screen with `H0Ver` in silver text.

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

- Click the `H0Ver` menu bar item and select **Lock Now** (or press `L` when the menu is open).
- When unlocked, the lock screen disappears but the app stays running in the menu bar.
- To quit completely, select **Quit** from the menu bar.

## Configuration

Select **Settings...** from the menu bar to open the Preferences window.

You can configure:
- **Video Path:** Choose a local `.mp4`, `.mov`, or `.m4v` file.
- **Password:** Set your unlock password (default is `hover`).
- **Lockout (Max Attempts):** Number of incorrect password attempts before a cooldown is enforced.
- **Lockout (Cooldown Duration):** Base cooldown time in seconds when locked out. Subsequent failed attempts will increase the lockout duration incrementally.

### Configuration Priority Order

1. **UserDefaults** (modified via the Settings UI)
2. **`.env` file** (if present next to the executable, in project root, or working directory)
3. **Environment variables**
4. **Defaults**

*(If you were using a `.env` file previously, its values will still be read if not overridden by the Settings UI).*

## Unlocking

Type the password directly and press **Return**. No need to click the field.

| Action | Shortcut |
|---|---|
| Submit password | Return |
| Touch ID / system auth | Fn+T |
| Backspace | Delete last character |
| Emergency quit (testing) | Esc ×5 or Cmd+Q |

- Clicks, drags, swipes, and gestures are disabled while locked.
- The password field has a frosted-glass blur effect over the video.
- One overlay window per display, kept frontmost at screen-saver level.
- Displays recreate automatically when screen parameters change.
- A live clock and date are displayed on the lock screen.
- After consecutive incorrect attempts, the password field displays a red border, blocks input, and shows a countdown timer.

## Notes

- The in-app password is for this app only — it is not your macOS login password unless you set it that way.
- Touch ID uses Apple's `LocalAuthentication` framework with `.deviceOwnerAuthentication` policy.
- Multi-monitor support is best-effort.
