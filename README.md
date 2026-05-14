# TwoFingerMiddleClick

A tiny macOS menu-bar utility that converts ordinary right-click events into middle clicks without moving the pointer.

## Build

```sh
chmod +x build-app.sh
./build-app.sh
```

The app bundle is written to `build/TwoFingerMiddleClick.app`.

## Run

Open `build/TwoFingerMiddleClick.app`, then approve the Accessibility prompt. The app posts middle clicks at the event location, so it does not warp or reposition the mouse.

## Notes

- Live finger counts use Apple’s private `MultitouchSupport.framework`.
- Existing right-click events are converted to middle clicks unless they happen during a live two-finger physical click frame.
- This is intentionally minimal: no login item, settings UI, or bundled icon yet.
