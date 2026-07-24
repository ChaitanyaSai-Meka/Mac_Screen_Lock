# Mac Gesture Lock

A macOS prototype that opens into a full-screen custom video screensaver with audio, then unlocks when you draw configured letters on the trackpad or mouse.

If no video is configured, or the configured file does not exist, the app displays a black fallback screen with `H0Ver`.

## Important security limitation

This is an app-level overlay, not a replacement for macOS LoginWindow, FileVault, Touch ID, password unlock, or the real system lock screen. A privileged user or someone with physical access may still bypass or quit apps. Keep normal macOS security enabled.

## Build

```bash
swift build
```

## Run with the H0Ver fallback

```bash
swift run mac-gesture-lock
```

Default unlock phrase is `L`.

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

## Configure unlock letters

Supported prototype letters are `L I V Z C O M N`.

```bash
UNLOCK_PHRASE=LO swift run mac-gesture-lock
```

or persist it:

```bash
defaults write MacGestureLock UnlockPhrase -string "LO"
```

## Use

1. Open the app. It creates full-screen overlay windows on all detected screens.
2. If a valid custom video path is set, the video loops full-screen and plays audio.
3. If not, the screen displays `H0Ver`.
4. Draw one unlock letter at a time by dragging on the trackpad or mouse.
5. When the full phrase matches, the overlay disappears.
6. Use the menu bar `H0Ver` item to lock again.
7. Emergency quit: press `Esc` five times or press `Command-Q`.

## Notes

- Trackpad drawing is captured as normal pointer drag events, so no private multitouch APIs are required.
- Recognition uses simple normalized stroke templates. It is good for a prototype, but training samples or a better recognizer would be needed for production.
- Multi-monitor support is best-effort. The app creates one high-level overlay window per detected screen.
