# Mac Gesture Lock

A macOS prototype that opens into a full-screen custom video screensaver with audio, then unlocks with Touch ID.

If no video is configured, or the configured file does not exist, the app displays a black fallback screen with `H0Ver`.

## Important security limitation

This is an app-level overlay, not a replacement for macOS LoginWindow, FileVault, Touch ID at the real system lock screen, password unlock, or the real system screen saver. A privileged user or someone with physical access may still bypass or quit apps. Keep normal macOS security enabled.

macOS does not let a normal app fully disable system-level gestures like Mission Control or Spaces swipes globally. This app uses all-screen, all-Spaces, high-level overlay windows and swallows local swipe/scroll/click events while locked to reduce accidental reveal, but the real secure solution is still the built-in macOS lock screen.

## Build

```bash
swift build
```

## Run with the H0Ver fallback

```bash
swift run mac-gesture-lock
```

The command keeps running while the overlay is active. Unlock it or use the emergency quit shortcut to return to the shell.

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

Touch ID is the only unlock path.

- Press `T`, Return, or use the menu bar item to start Touch ID.
- Clicks, drawing gestures, drags, swipes, and random shortcuts do not unlock.
- The app creates one overlay window per detected display and keeps them at screen-saver level across Spaces.
- Emergency quit for prototype testing: press `Esc` five times or press `Command-Q`.

## Notes

- Touch ID uses Apple's `LocalAuthentication` framework with the biometric-only policy.
- Gesture recognition was removed completely because clicking/drawing caused crashes on your machine.
- Multi-monitor support is best-effort. The app recreates overlay windows when screen parameters change.
