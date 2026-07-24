# Mac Gesture Lock

A macOS prototype that opens into a full-screen custom video screensaver with audio, then unlocks with either the configured drawn-letter gesture phrase or Touch ID.

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

The command keeps running while the overlay is active. Unlock it or use the emergency quit shortcut to return to the shell.

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

## Configure gesture unlock letters

Supported prototype letters are `L I V Z C O M N`.

```bash
UNLOCK_PHRASE=LO swift run mac-gesture-lock
```

or persist it:

```bash
defaults write MacGestureLock UnlockPhrase -string "LO"
```

## Unlocking

There are exactly two intended unlock paths:

1. Draw the configured letter phrase one letter at a time on the trackpad or mouse.
2. Press `T`, Return, or use the menu bar item to start Touch ID, then authenticate successfully.

Random swipes, unrelated gestures, and normal keyboard shortcuts do not unlock the app. A swipe is treated only as a candidate drawn letter and must match the configured phrase in sequence.

## Use

1. Open the app. It creates full-screen overlay windows on all detected screens.
2. If a valid custom video path is set, the video loops full-screen and plays audio.
3. If not, the screen displays `H0Ver`.
4. Draw the configured phrase or authenticate with Touch ID to unlock.
5. Use the menu bar `H0Ver` item to lock again.
6. Emergency quit for prototype testing: press `Esc` five times or press `Command-Q`.

## Notes

- Touch ID uses Apple's `LocalAuthentication` framework with the biometric-only policy.
- Gesture recognition uses simple normalized stroke templates. It rejects unrecognized swipes by resetting progress.
- Common keys and shortcuts are consumed by the overlay while locked. They do not dismiss it.
- Multi-monitor support is best-effort. The app creates one high-level overlay window per detected screen.
