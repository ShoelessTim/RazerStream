# RazerStream software brief

Written as a standalone reference for planning v2 and beyond; accurate as of
tag v1.5.0 on the main branch of github.com/ShoelessTim/RazerStream.

## What it is

A native macOS app that replaces the retired Loupedeck software for the Razer
Stream Controller (USB VID 0x1532, PID 0x0D06); 12 touchscreen tiles arranged
4x3, 6 rotary encoders with press, 8 physical buttons with color LEDs. Free,
MIT licensed, publicly released with a Developer ID notarized build and a
Homebrew tap.

## Architecture, three layers

**RazerStreamKit** (`Packages/RazerStreamKit`, its own standalone SPM package
since v1.4.0, ~900 lines). The protocol library. Pure Foundation plus POSIX
serial I/O and IOKit for device discovery; no AppKit or SwiftUI, so it is
reusable headless and portable to Linux with a small shim. Handles: USB
serial transport over a CDC port, the WebSocket upgrade handshake, RFC 6455
frame encode and decode (client frames masked with an all zero key, server
frames unmasked), the message protocol (length, command byte, transaction id,
payload), RGB565 framebuffer writes, and an AsyncStream of DeviceEvent for
input. The app depends on it by local path; anything else wanting to talk to
this hardware can depend on just this package without pulling in the app.

**RazerStreamCLI** (`Sources/RazerStreamCLI`). A thin `rstream` command line
tool: list, monitor, brightness, test-pattern, version. Useful for debugging
and for anyone building a non-macOS frontend against the kit.

**RazerStreamApp** (`Sources/RazerStreamApp`, ~2800 lines). The SwiftUI
application. Key files:

- `Profile.swift`: the data model. A Profile has multiple Pages; each Page has
  12 TileConfig, 6 KnobConfig, 8 ButtonConfig. A knob can also be pinned as
  "global" (shared across every page instead of set per page), backed by a
  parallel `globalKnobs`/`knobIsGlobal` pair on Profile; ProfileStore's
  `resolvedCurrentPage` substitutes the pinned config in wherever a page is
  actually dispatched or rendered. ControlAction covers open app, open URL,
  shell command, AppleScript, keystroke, media keys, volume, screen
  brightness, page navigation, show app. ControlMode covers tap, toggle,
  momentary, and shiftPage. Persisted as JSON in Application Support, with a
  tolerant decoder for old profile shapes; also exportable/importable as a
  standalone single-profile `.razerstream` file (Settings > History).
- `DeviceManager.swift`: owns the live connection, auto reconnect on unplug or
  crash, routes device events to actions based on the current page and
  control mode, paces framebuffer writes (~60ms apart, the device drops
  frames if you push faster), runs the LED cascade, brightness fade-in, and
  screen test pattern on connect. Also handles knob acceleration (fast
  consecutive turns step 3x), idle dimming of the screen and button LEDs
  (off by default), and app-switching page selection via `AppSwitchMonitor`.
- `ActionEngine.swift`: executes a ControlAction; CGEvent for keystrokes and
  media keys (gated on the Accessibility permission), NSWorkspace for apps
  and URLs, Process for shell, NSAppleScript on the main thread only (it is
  not thread safe). Takes an `amount` parameter so DeviceManager's knob
  acceleration can scale volume/brightness steps without a separate code path.
- `TileRenderer.swift`: renders TileConfig and KnobConfig into RGB565 buffers
  using CoreGraphics; handles SF Symbols, bundled icon packs, custom images,
  color backgrounds, the toggle on-state ring, and live content (clock,
  CPU/RAM meter).
- `SystemMeter.swift`: CPU and memory usage via the same public Mach host
  APIs Activity Monitor uses (`host_statistics`/`host_statistics64`); no
  private frameworks.
- `KnobPreferences.swift`: the global clockwise-increases handedness setting,
  and `KnobRotationMode` (None/Volume/Brightness/Page Navigation/Track/Custom)
  that turns two hand-wired direction pickers into one choice.
- `HapticFeedback.swift` / `IdlePreferences.swift`: small UserDefaults-backed
  device preferences (haptics on/off + pattern; idle-dim on/off + timeout),
  same pattern as the handedness setting above.
- `IconPacks.swift` / `IconPicker.swift` / `RecentIcons.swift`: bundled Lucide
  and Bootstrap icon packs plus user-added folders of PNG or SVG, rasterized
  at high resolution so small stroke icons stay crisp; a searchable picker
  UI with System/Recent/pack tabs.
- `ContentView.swift`: the main window; a live mirror of the physical device,
  click any tile, knob, or button to edit it in a trailing inspector.
- `ModeEditor.swift` / `KeystrokeRecorder.swift`: shared editors, notably a
  press-the-real-keys shortcut recorder instead of typed combo strings.
- `SettingsView.swift`: General (appearance, launch at login, Accessibility
  status), Device (status, brightness, handedness, idle dimming, self test),
  Haptics (on/off, pattern, test), Apps (app-switching page mappings), Icons
  (manage packs and user folders), History (version snapshots, profile
  duplicate/export/import), About.
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

## What is shipped and working (v1.5.0)

v1.5.0 adds multi-action macros on top of the stabilized 1.4.7 line
(LED brightness knobs, live tiles, page +/−, Xcode 16.4 build fix).

- Full input: all tiles, knobs (turn and press), buttons, touchscreen
- Full output: tile images (SF Symbols, bundled/user icon packs, custom
  images, colors), knob strip labels and icons (plus live content), button
  LEDs, screen and button-LED brightness
- Behavior modes: tap, toggle (stateful, icon and LED reflect state),
  momentary, shift (hold to reveal another page)
- Actions: app launch, URL, shell, AppleScript, recorded keystrokes, media
  keys (native volume HUD), screen brightness, button LED brightness, page
  navigation, show app window, and multi-step macros (sequence of leaf
  actions with per-step delay)
- Knob rotation presets (Volume, Screen Brightness, Button LED Brightness,
  Screen + LED Brightness, Page Navigation, Track) as single choices with a
  shared handedness setting; fast turns accelerate the step. Brightness knobs
  use a dedicated `pushBrightness` path so continuous turns reach the LEDs
  instead of cancelling a full page redraw mid-flight
- A knob can be pinned to share its config across every page
- Multiple pages per profile, including automatic page-switching based on
  the frontmost app (Settings > Apps); sidebar has a native +/- bar at the
  top to add or remove pages (context-menu delete still works too)
- Live tiles: clock, CPU/RAM meter, disk free space (per-volume), on both
  tiles and knob strips (knob strips use small pie charts for meters)
- Haptic feedback on press (device-dependent), Settings > Haptics tab
- Idle dimming of the screen and button LEDs after inactivity, off by
  default; the status light is never touched, so connection state always
  stays visible; LED idle writes are paced so the device does not drop them
- Native `.razerstream` single-profile export/import (Settings > History)
- Profile version history (autosave snapshots), separate from export/import
- Auto reconnect on device unplug and crash recovery; a stale-serial-buffer
  flush on connect was added in v1.4.1 for a "screen doesn't come up after
  quit/relaunch without unplugging" report, not yet confirmed as fully fixed
- Native color panel, dark mode following the system, launch at login
- Device self test: LED rainbow sweep plus a full screen test pattern
- Settings window, in-app Help window, custom deck-shaped menu bar icon
- Developer ID signed, notarized, GitHub Release, Homebrew tap, CI on
  push and pull request

## What does not exist yet

- Any Adobe style live panel API integration (Premiere Pro, etc.); Loupedeck
  had this, RazerStream only has static keystroke and script actions
- Stream Deck / Loupedeck profile import (their file formats, not attempted)
- Now-playing tiles with album art (needs Apple's private MediaRemote
  framework; flagged as risky, not attempted) and a calendar next-up tile
- Multi-action macros (fire a sequence of actions from one control); called
  out directly by a user as a must-have for a real Loupedeck replacement
- Mouse scroll as a knob rotation preset (LED brightness as a knob preset
  shipped in the 1.4.7 line)
- Profile-per-app as an alternative to the current page-per-app-within-one-
  profile model; a real design fork, not decided
- Touch gestures beyond tap; two-finger swipe was shipped in v1.4.1 and
  pulled in v1.4.2 (physical bezel ridges make the gesture unpleasant on
  this hardware, independent of the code)
- Idle sleep and wake for the display (idle *dimming* exists; full sleep
  does not)
- Webhooks, Home Assistant, MQTT
- A plugin or extension API for third party actions; a concrete real-world
  requirement (full-tile/full-knob custom image drawing at 10-20fps, plus
  two-way data) is documented in ROADMAP.md from actual user feedback
- Loupedeck CT hardware support; different device, no protocol capture to
  work from yet
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
