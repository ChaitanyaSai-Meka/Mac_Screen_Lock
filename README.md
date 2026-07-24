# Mac Gesture Lock

A macOS prototype that opens into a full-screen custom video screensaver with audio, then unlocks with Touch ID or your Mac password.

If no video is configured, or the configured file does not exist, the app displays a black fallback screen with `H0Ver`.

## Important security limitation

This is an app-level overlay, not a replacement for macOS LoginWindow, FileVault, Touch ID at the real system lock screen, password unlock, or the real system screen saver. A privileged user or someone with physical access may still bypass or quit apps. Keep normal macOS security enabled.

macOS does not let a normal app fully disable every system-level gesture globally. This app now tries to capture all displays while locked, uses all-screen high-level overlay windows, and swallows local swipe/scroll/click events. That should reduce the four-finger Spaces reveal, but the only fully secure solution is still Apple’s lock screen.

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

Touch ID or your Mac password unlocks the app.

- Press `T`, Return, or use the menu bar item to start authentication.
- macOS decides whether to show Touch ID, password fallback, or both.
- Clicks, drawing gestures, drags, swipes, and random shortcuts do not unlock.
- The app creates one overlay window per detected display and attempts to capture all displays while locked.
- Emergency quit for prototype testing: press `Esc` five times or press `Command-Q`.

## Notes

- Authentication uses Apple's `LocalAuthentication` framework with `.deviceOwnerAuthentication` so password fallback is allowed.
- Gesture recognition was removed completely because clicking/drawing caused crashes on your machine.
- Display capture is released on successful unlock or emergency quit.
- Multi-monitor support is best-effort. The app recreates overlay windows when screen parameters change.
