# Launch post

Ready to paste for Reddit (r/Loupedeck, r/razer, r/macapps), Razer Insider,
or as a Show HN. Trim to taste.

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

Requires macOS 14 or later. Not affiliated with Razer, Loupedeck, or Logitech;
just a community keeping good hardware alive.
