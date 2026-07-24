# Mac Gesture Lock

A macOS prototype that opens into a full-screen custom video screensaver with audio, then unlocks with Touch ID.

If no video is configured, or the configured file does not exist, the app displays a black fallback screen with `H0Ver`.

## Important security limitation

This is an app-level overlay, not a replacement for macOS LoginWindow, FileVault, Touch ID at the real system lock screen, password unlock, or the real system screen saver. A privileged user or someone with physical access may still bypass or quit apps. Keep normal macOS security enabled.

## Build

```bash
swift build
```

## Run with the H0Ver fallback

```bash
swift run mac-gesture-lock
```

## Run with a custom video screensaver and audio

Use any local video file supported by AVPlayer, such as `.mp4`, `.mov`, or `.m4v`. Audio in the video is enabled by default.

```bash
SCREENSAVER_VIDEO="/Users/you/Movies/screensaver.mp4" swift run mac-gesture-lock
```

You can also persist the path with user defaults:

```bash
defaults write MacGestureLock ScreensaverVideo -string "/Users/you/Movies/screensaver.mp4"
swift run mac-gesture-lock
```

## Unlocking

Unlocking is Touch ID only.

- The app asks for Touch ID automatically when it locks.
- Click anywhere, press Return, press Space, or use the menu bar item to retry Touch ID.
- Drawn gestures are disabled and are intentionally ignored. They cannot unlock the app.
- If Touch ID is not available on the Mac, the app stays locked and shows an error.

## Use

1. Open the app. It creates full-screen overlay windows on all detected screens.
2. If a valid custom video path is set, the video loops full-screen and plays audio.
3. If not, the screen displays `H0Ver`.
4. Authenticate with Touch ID to unlock.
5. Use the menu bar `H0Ver` item to lock again.
6. Emergency quit for prototype testing: press `Esc` five times or press `Command-Q`.

## Notes

- This version intentionally removed the drawn-letter recognizer so no gesture can unlock the app.
- Touch ID uses Apple's `LocalAuthentication` framework with the biometric-only policy.
- Multi-monitor support is best-effort. The app creates one high-level overlay window per detected screen.
