# RazerStream software brief

Written as a standalone reference for planning v2 and beyond; accurate as of
tag v1.1.1 on the main branch of github.com/ShoelessTim/RazerStream.

## What it is

A native macOS app that replaces the retired Loupedeck software for the Razer
Stream Controller (USB VID 0x1532, PID 0x0D06); 12 touchscreen tiles arranged
4x3, 6 rotary encoders with press, 8 physical buttons with color LEDs. Free,
MIT licensed, publicly released with a Developer ID notarized build and a
Homebrew tap.

## Architecture, three layers

**RazerStreamKit** (`Sources/RazerStreamKit`, ~900 lines). The protocol
library. Pure Foundation plus POSIX serial I/O and IOKit for device discovery;
no AppKit or SwiftUI, so it is reusable headless and portable to Linux with a
small shim. Handles: USB serial transport over a CDC port, the WebSocket
upgrade handshake, RFC 6455 frame encode and decode (client frames masked with
an all zero key, server frames unmasked), the message protocol (length,
command byte, transaction id, payload), RGB565 framebuffer writes, and an
AsyncStream of DeviceEvent for input.

**RazerStreamCLI** (`Sources/RazerStreamCLI`). A thin `rstream` command line
tool: list, monitor, brightness, test-pattern, version. Useful for debugging
and for anyone building a non-macOS frontend against the kit.

**RazerStreamApp** (`Sources/RazerStreamApp`, ~2800 lines). The SwiftUI
application. Key files:

- `Profile.swift`: the data model. A Profile has multiple Pages; each Page has
  12 TileConfig, 6 KnobConfig, 8 ButtonConfig. ControlAction is an enum
  covering open app, open URL, shell command, AppleScript, keystroke, media
  keys, volume, page navigation, show app. ControlMode covers tap, toggle,
  momentary, and shiftPage. Persisted as JSON in Application Support, with a
  tolerant decoder for old profile shapes.
- `DeviceManager.swift`: owns the live connection, auto reconnect on unplug or
  crash, routes device events to actions based on the current page and
  control mode, paces framebuffer writes (~60ms apart, the device drops
  frames if you push faster), runs the LED cascade and screen test pattern.
- `ActionEngine.swift`: executes a ControlAction; CGEvent for keystrokes and
  media keys (gated on the Accessibility permission), NSWorkspace for apps
  and URLs, Process for shell, NSAppleScript on the main thread only (it is
  not thread safe).
- `TileRenderer.swift`: renders TileConfig and KnobConfig into RGB565 buffers
  using CoreGraphics; handles SF Symbols, bundled icon packs, custom images,
  color backgrounds, and the toggle on-state ring.
- `IconPacks.swift` / `IconPicker.swift`: bundled Lucide and Bootstrap icon
  packs plus user-added folders of PNG or SVG, rasterized at high resolution
  so small stroke icons stay crisp; a searchable picker UI.
- `ContentView.swift`: the main window; a live mirror of the physical device,
  click any tile, knob, or button to edit it in a trailing inspector.
- `ModeEditor.swift` / `KeystrokeRecorder.swift`: shared editors, notably a
  press-the-real-keys shortcut recorder instead of typed combo strings.
- `SettingsView.swift`: General (appearance, launch at login, Accessibility
  status), Device (status, brightness, self test), Icons (manage packs and
  user folders), About.
- `HelpView.swift`: full in-app user guide, wired to the Help menu and Cmd+?.

## Wire protocol (documented fully in PROTOCOL.md)

Worth knowing without reading the whole file: the device is a USB CDC serial
port, 9600 8N1, that speaks a WebSocket-over-serial dialect. The upgrade
handshake needs a trailing blank line or the device never answers. Client to
device frames must set the mask bit with an all zero key even though masking
with zero is a no-op. Brightness is a single byte, a stray leading zero blanks
the panel. One display id (0x004D) covers the whole 480x270 space; the center
tile grid starts at x=60. Control ids: 1 to 6 are knob presses (left column
top to bottom, then right), 7 to 14 are the physical buttons left to right;
button id 7's LED is the device status light and must never be written.

## What is shipped and working (v1.1.1)

- Full input: all tiles, knobs (turn and press), buttons, touchscreen
- Full output: tile images (SF Symbols, bundled/user icon packs, custom
  images, colors), knob strip labels and icons, button LEDs, brightness
- Behavior modes: tap, toggle (stateful, icon and LED reflect state),
  momentary, shift (hold to reveal another page)
- Actions: app launch, URL, shell, AppleScript, recorded keystrokes, media
  keys (native volume HUD), page navigation, show app window
- Multiple pages per profile
- Auto reconnect on device unplug and crash recovery
- Native color panel, dark mode following the system, launch at login
- Device self test: LED rainbow sweep plus a full screen test pattern
- Settings window, in-app Help window, custom deck-shaped menu bar icon
- Developer ID signed, notarized, GitHub Release, Homebrew tap, CI on
  push and pull request

## What does not exist yet

- App-switching profiles (auto swap layout based on frontmost app); explicitly
  deprioritized by the maintainer in favor of manual pages
- Any Adobe style live panel API integration (Premiere Pro, etc.); Loupedeck
  had this, RazerStream only has static keystroke and script actions
- Profile import or export as a shareable file
- Live tiles (clock, now playing, system meters)
- Haptics (the device supports a vibration command, unused so far)
- Touch gestures beyond tap (no swipe between pages)
- Knob acceleration
- Idle sleep and wake for the display
- Webhooks, Home Assistant, MQTT
- A plugin or extension API for third party actions
- Any non-macOS build; Linux is scoped as a good first contribution in the
  roadmap but not started

## Known constraints worth remembering

- The app is not sandboxed and never will be if it wants to keep shell,
  AppleScript, and system-wide keystroke actions; this rules out the Mac App
  Store, which is why distribution is Developer ID plus notarization instead
- Accessibility permission grant is tied to the code signature; it broke
  across early ad hoc rebuilds, which is why the app now signs with a stable
  Developer ID identity for releases
- Framebuffer writes must be paced; the device's serial buffer overruns and
  silently drops frames if you push too fast
- NSAppleScript must run on the main thread or it fails silently
- The maintainer (Tim) writes no dashes in comments, commit messages, or docs;
  semicolons instead

## Full docs in the repo

README.md (features, install), PROTOCOL.md (complete wire protocol),
CONTRIBUTING.md (build and style), SECURITY.md, ROADMAP.md (the tracked v2
plan this brief feeds into).
