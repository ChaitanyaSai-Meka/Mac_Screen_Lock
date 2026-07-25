# H0Ver — Mac Screen Lock

A macOS app that overlays a full-screen video screensaver with audio, unlockable via an in-app password or Touch ID. The password field uses a native frosted-glass (liquid glass) effect.

If no video is configured, the app displays a black screen with `H0Ver` in silver text.

## Security Limitation

This is an app-level overlay, **not** a replacement for macOS LoginWindow, FileVault, or the system lock screen. A privileged user or someone with physical access may still bypass or quit the app. Keep normal macOS security enabled.

## Build

```bash
swift build
```

## Run

```bash
swift run mac-gesture-lock
```

The app keeps running while the overlay is active. Unlock it or use the emergency quit shortcut to return to the shell.

## Configuration

### `.env` file (recommended)

The easiest way to configure H0Ver. Create a `.env` file in the project root:

```env
# Path to video file (.mp4, .mov, .m4v)
VIDEO_PATH=/path/to/your/video.mp4

# Password to unlock (default: hover)
LOCK_PASSWORD=hover
```

The `.env` file is automatically detected next to the executable, in the project root, or in the current working directory.

### Environment variables

```bash
SCREENSAVER_VIDEO="/path/to/video.mp4" LOCK_PASSWORD="my-secret" swift run mac-gesture-lock
```

### UserDefaults

```bash
defaults write MacGestureLock ScreensaverVideo -string "/path/to/video.mp4"
defaults write MacGestureLock AppPassword -string "my-secret"
```

**Priority order:** `.env` file → UserDefaults → environment variables → defaults.

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

## Notes

- The in-app password is for this app only — it is not your macOS login password unless you set it that way.
- Touch ID uses Apple's `LocalAuthentication` framework with `.deviceOwnerAuthentication` policy.
- Multi-monitor support is best-effort.
