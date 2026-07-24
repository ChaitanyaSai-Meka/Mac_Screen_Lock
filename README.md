# Mac Gesture Lock

A macOS prototype that opens into a full-screen custom video screensaver with audio, then unlocks with an in-app password or optional Touch ID.

If no video is configured, or the configured file does not exist, the app displays a black fallback screen with `H0Ver`.

## Important security limitation

This is an app-level overlay, not a replacement for macOS LoginWindow, FileVault, Touch ID at the real system lock screen, password unlock, or the real system screen saver. A privileged user or someone with physical access may still bypass or quit apps. Keep normal macOS security enabled.

macOS does not let a normal app fully disable every system-level gesture globally. This app uses all-screen high-level overlay windows, AppKit locked presentation options, and local swipe/scroll/click swallowing. That reduces accidental reveal without blanking the display, but the only fully secure solution is still Apple’s lock screen.

## Build

```bash
swift build
```

## Run with the H0Ver fallback

```bash
swift run mac-gesture-lock
```

The command keeps running while the overlay is active. Unlock it or use the emergency quit shortcut to return to the shell.

## Set the app password

Default app password is `hover`.

Set it for one run:

```bash
LOCK_PASSWORD="my-secret" swift run mac-gesture-lock
```

Or persist it:

```bash
defaults write MacGestureLock AppPassword -string "my-secret"
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

The screen has a visible password box. Type the app password directly and press Return. You do not need to click the box.

Optional Touch ID/system authentication remains available by pressing `T`, but the in-app password is the reliable fallback.

- Clicks, drawing gestures, drags, swipes, and random shortcuts do not unlock.
- Backspace edits the password entry.
- The app creates one overlay window per detected display and keeps them frontmost at screen-saver level.
- Emergency quit for prototype testing: press `Esc` five times or press `Command-Q`.

## Notes

- The in-app password is for this prototype only. It is not your macOS login password unless you choose to set it that way.
- Optional Touch ID uses Apple's `LocalAuthentication` framework.
- Gesture recognition was removed completely because clicking/drawing caused crashes on your machine.
- Display capture was removed because it caused a completely black screen instead of rendering `H0Ver` or video.
- Multi-monitor support is best-effort. The app recreates overlay windows when screen parameters change.
