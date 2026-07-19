# RazerStream

[![CI](https://github.com/ShoelessTim/RazerStream/actions/workflows/ci.yml/badge.svg)](https://github.com/ShoelessTim/RazerStream/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/ShoelessTim/RazerStream)](https://github.com/ShoelessTim/RazerStream/releases/latest)

A native macOS app for the **Razer Stream Controller**, the 8-button, 6-knob,
touchscreen macro deck that Loupedeck built and Logitech orphaned. When the
official software was retired the hardware still worked; this project talks to
it directly so the device keeps living.

RazerStream is faster and lighter than the app it replaces, and it is a
community project; fork it, extend it, send pull requests.

**Current release: [v1.4.72](https://github.com/ShoelessTim/RazerStream/releases/tag/v1.4.72)**

Not affiliated with Razer, Loupedeck, or Logitech.

## Features

- Full control of all 12 touchscreen tiles, 6 rotary encoders (turn and
  press), and the 8 physical buttons with color LEDs
- Draw labels, colors, SF Symbols icons, or custom images to any tile or knob;
  a searchable icon library (SF Symbols, bundled Lucide/Bootstrap packs, your
  own folders of PNG/SVG files) with a Recent tab
- Behavior modes per control: tap, toggle (stateful, like play/pause),
  momentary (hold), and shift (hold to reveal another page)
- Actions: open app, open URL, shell command, AppleScript, recorded keystroke,
  media keys, volume with the native on-screen HUD, screen brightness, button
  LED brightness, page navigation, and show the app window
- Knob rotation presets: Volume, Screen Brightness, Button LED Brightness,
  Screen + LED Brightness, Page Navigation, and Track skip are each a single
  choice instead of hand-wiring clockwise and counterclockwise separately,
  with one Settings toggle to flip which direction counts as "up" for all of
  them; fast turns step further. A knob can also be pinned so its config is
  shared across every page instead of set up per page.
- Multiple pages per profile (sidebar +/- to add or remove); switch manually,
  use shift-hold layers, or let RazerStream switch pages automatically based
  on which app is frontmost
- Live tiles that redraw themselves: a clock, a CPU/RAM usage meter, and
  disk free space on a chosen volume (bars on tiles; pie charts on knob strips)
- Haptic feedback on press (device-dependent), with a pattern picker
- Idle dimming: screen and button LEDs fade after inactivity and wake on any
  input; the status light is never touched, so connection state always
  stays visible
- Export or import a single profile as a standalone `.razerstream` file
- Profile version history (autosave snapshots) in place of undo/redo
- Native color panel (crayons included), dark mode that follows the system,
  launch at login, and a device self-test with LED sweep and screen pattern

## What's new in 1.4.72

Stabilization release for the 1.4.7 line (not a big feature dump).

- **Fixed:** page add/delete controls missing from the sidebar on some window
  sizes and macOS builds ([#1](https://github.com/ShoelessTim/RazerStream/issues/1)).
  The +/- bar is now a native control at the top of the page list.
- **Included from the 1.4.7 line:** Button LED Brightness and Screen + LED
  Brightness knob presets; dedicated brightness push so continuous knob turns
  actually reach the LEDs; disk free-space live tile; pie charts on knob
  strips; idle LED dimming pacing; custom SVG size normalization (please
  retest if you hit [#2](https://github.com/ShoelessTim/RazerStream/issues/2)).

Full notes: [release v1.4.72](https://github.com/ShoelessTim/RazerStream/releases/tag/v1.4.72).
Docs and FAQ: [project wiki](https://github.com/ShoelessTim/RazerStream/wiki).

## Requirements

- macOS 14 or later
- A Razer Stream Controller (USB VID 0x1532, PID 0x0D06)
- Xcode 16 or later to build from source

## Install (no building required)

With Homebrew:

```sh
brew tap shoelesstim/tap
brew install --cask razerstream
# later:
brew upgrade --cask razerstream
```

Or by hand:

1. Download `RazerStream-v1.4.72.zip` from the
   [latest release](https://github.com/ShoelessTim/RazerStream/releases/latest)
2. Unzip and drag `RazerStream.app` into `/Applications`
3. Double-click to open; releases are Developer ID signed and notarized by
   Apple, so there are no warnings

Either way, grant the Accessibility permission when prompted; keystrokes and
media keys need it.

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

- `Packages/RazerStreamKit` the protocol library, its own standalone Swift
  package; serial transport, WebSocket framing, device commands and events.
  Depend on this alone (by local path, or fork it out) to talk to the
  hardware from any Swift program without pulling in the CLI or the app.
- `Sources/RazerStreamCLI` the `rstream` command-line tool.
- `Sources/RazerStreamApp` the SwiftUI application.
- `PROTOCOL.md` the reverse-engineered wire protocol, documented byte by byte.
- `ROADMAP.md` where this is going.
- [Wiki](https://github.com/ShoelessTim/RazerStream/wiki) install notes, FAQ,
  changelog, and roadmap for contributors.

## Other platforms

The app is macOS only and staying that way, but the project is built to be
ported. `RazerStreamKit` is Foundation plus POSIX serial I/O and is one small
device-discovery shim away from compiling on Linux Swift, which would bring the
`rstream` CLI along nearly for free. The complete wire protocol lives in
[PROTOCOL.md](PROTOCOL.md); a Linux GUI (GTK or Qt) or a Windows app (C# is the
sane choice there) can be built on top of it without ever sniffing a byte.
Contributions on this front are very welcome; see the roadmap.

## Credits

Protocol groundwork stands on the shoulders of the community reverse
engineering efforts, especially the foxxyz/loupedeck project. Thank you.

## License

MIT; see [LICENSE](LICENSE).
