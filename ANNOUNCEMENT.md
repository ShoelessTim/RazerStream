# Announcement posts

## Update post (v1.4.72) — paste for Reddit

Already posted to r/loupedeck (2026-07-15 launch, 2026-07-17 v1.4.0 follow-up).
Use this as a reply in that thread and/or a short new post if the sub allows.

Title: RazerStream 1.4.72: page add/delete fix, LED brightness knobs, live tiles

Body:

Quick update on RazerStream, the free native macOS app for the orphaned Razer Stream Controller / Loupedeck Live.

**1.4.72** is a tidy stabilization of the 1.4.7 line, not a huge feature dump. Goal: something solid you can run while the next bug-fix pass happens.

### Fixed

- **Couldn't add or delete pages** in the sidebar on some setups. The +/- bar could vanish depending on window size / layout. It's now a real native control at the top of the page list. (GitHub issue #1)

### From the 1.4.7 line (if you skipped those)

- Knob presets: **Button LED Brightness**, and **Screen + LED Brightness** together, on top of Volume / Screen Brightness / Page Nav / Track
- Turning an LED brightness knob actually moves the LEDs now (continuous turns used to cancel the write mid-flight)
- Live tiles: CPU/RAM, **disk free space** (pick a volume); pie charts on the knob strips
- Idle dimming paces LED writes so they don't get silently dropped by the serial buffer
- Custom SVG sizing path for user icon libraries (if you still see tiny SVGs on knobs/tiles after 1.4.72, please comment on issue #2 with OS version)

### Download

- Latest: https://github.com/ShoelessTim/RazerStream/releases/latest
- Homebrew: `brew upgrade --cask razerstream` (after `brew tap shoelesstim/tap`)
- Wiki / FAQ: https://github.com/ShoelessTim/RazerStream/wiki

Still macOS 14+, Developer ID signed and notarized. Still free, still open source, still not affiliated with Razer / Loupedeck / Logitech.

Known open: multi-action macros, mouse-scroll knob preset, plugin API, Loupedeck CT, and confirmation that SVG icons look right on macOS 26.x. Happy for bug reports and PRs.

---

## Original launch post (v1.0)

Ready to paste for platforms that haven't seen the project yet. For r/loupedeck
prefer the update post above (or a reply in the existing thread).

Title: RazerStream: a free, native macOS app that revives the orphaned Razer Stream Controller

When Logitech acquired Loupedeck and retired the software, the Razer Stream
Controller became a paperweight; 8 keys, 6 dials, and a touchscreen with
nothing to drive them. No replacement, no update, just a dead app.

So I reverse-engineered the protocol and wrote a new one. RazerStream is a
native macOS app that brings the whole device back: every LCD key, the
touchscreen, all six encoders, and the button LEDs. It is faster and lighter
than the software it replaces, it is free, and it is open source.

What it does:

- Draw labels, colors, icons (full SF Symbols library), or your own images to
  any key
- Behavior modes per control: tap, toggle (stateful, like play/pause),
  momentary hold, and shift to reveal another page while held
- Actions: launch apps, open URLs, run shell commands or AppleScript, recorded
  keystrokes, media keys with the native volume HUD, and multi-page layouts
- Native color picker, dark mode that follows the system, launch at login, and
  a full device self-test

It is built on a clean Swift protocol library, and the reverse-engineered wire
format is documented byte by byte in PROTOCOL.md if you want to build your own
tools on top.

Download: https://github.com/ShoelessTim/RazerStream/releases/latest
Source: https://github.com/ShoelessTim/RazerStream

Releases are Developer ID signed and notarized by Apple; download, drag to
Applications, double-click. Requires macOS 14 or later. Not affiliated with
Razer, Loupedeck, or Logitech; just a community keeping good hardware alive.
