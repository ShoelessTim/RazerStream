# RazerStream

A native macOS app for the **Razer Stream Controller**, the 8-button, 6-knob,
touchscreen macro deck that Loupedeck built and Logitech orphaned. When the
official software was retired the hardware still worked; this project talks to
it directly so the device keeps living.

RazerStream is faster and lighter than the app it replaces, and it is a
community project; fork it, extend it, send pull requests.

Not affiliated with Razer, Loupedeck, or Logitech.

## Features

- Full control of all 8 LCD tiles, the touchscreen surface, 6 rotary encoders
  (turn and press), and the 8 physical buttons with color LEDs
- Draw labels, colors, SF Symbols icons, or custom images to any tile
- Behavior modes per control: tap, toggle (stateful, like play/pause),
  momentary (hold), and shift (hold to reveal another page)
- Actions: open app, open URL, shell command, AppleScript, recorded keystroke,
  media keys (play/pause, next, previous), volume with the native on-screen HUD,
  page navigation, and show the app window
- Multiple pages per profile; switch or use them as shift layers
- Native color panel (crayons included), dark mode that follows the system,
  launch at login, and a device self-test with LED sweep and screen pattern

## Requirements

- macOS 14 or later
- A Razer Stream Controller (USB VID 0x1532, PID 0x0D06)
- Xcode 16 or later to build

## Build and run

```sh
swift build -c release
./scripts/make_app.sh release install
open /Applications/RazerStream.app
```

`make_app.sh` assembles a signed `RazerStream.app`. Passing `install` copies it
to `/Applications`. Keystrokes and media keys need the macOS Accessibility
permission; the app shows a prompt and a status chip when it is missing.

There is also a small CLI for poking at the hardware:

```sh
swift run rstream monitor        # print every button, knob, and touch event
swift run rstream test-pattern   # draw a color test to the screen
swift run rstream brightness 7
```

## Project layout

- `Sources/RazerStreamKit` the protocol library; serial transport, WebSocket
  framing, device commands and events. Depend on this alone to talk to the
  hardware from any Swift program.
- `Sources/RazerStreamCLI` the `rstream` command-line tool.
- `Sources/RazerStreamApp` the SwiftUI application.
- `PROTOCOL.md` the reverse-engineered wire protocol, documented byte by byte.
- `ROADMAP.md` where this is going.

## Credits

Protocol groundwork stands on the shoulders of the community reverse
engineering efforts, especially the foxxyz/loupedeck project. Thank you.

## License

MIT; see [LICENSE](LICENSE).
