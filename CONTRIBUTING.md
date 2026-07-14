# Contributing

Pull requests welcome. This is a community project for orphaned hardware; the
goal is to keep the Razer Stream Controller useful.

## Building

```sh
swift build -c release
./scripts/make_app.sh release install
```

macOS 14 or later and Xcode 16 or later. The app needs the Accessibility
permission for keystrokes and media keys.

## Style

- No double dashes and no em dashes in comments, docs, or commit messages; join
  clauses with semicolons or split into sentences.
- Match the surrounding code; modern Swift concurrency, small focused types.
- The protocol layer (`RazerStreamKit`) stays free of AppKit and SwiftUI so it
  can be reused headless.

## Where things live

- Wire protocol details go in `PROTOCOL.md`; if you learn something new about
  the hardware, write it down there.
- The app talks to the device only through `RazerStreamKit`; keep that boundary.

## Pull requests

- One focused change per PR.
- Describe what you tested, ideally against real hardware.
- Device quirks and new firmware findings are especially valuable; include them.

## Reporting device behavior

If your unit behaves differently (a different firmware, id map, or PID), open an
issue with the firmware version, the `rstream monitor` output for the controls
in question, and what you expected.
