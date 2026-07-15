# RazerStream V2 Roadmap

V1 status: shipped and hardware verified. Protocol library, pages, icon library,
behavior modes (tap / toggle / momentary / shift), keystroke recorder, media keys,
button LEDs, dark mode, installed app bundle. Faster than the Loupedeck app ever was.

Style rule for this repo: no double dashes and no em dashes in comments, docs,
or commit messages; join clauses with semicolons instead.

## Theme for V2

Two tracks: make it look and feel like a first-party Apple tool; make it a real
open source community project. Everything below is ordered; top items first.

## Track 1: Apple-native UI pass (HIG)

Goal: a stranger opens the app and assumes Apple shipped it.

1. Window structure
   - NavigationSplitView with a real sidebar: Profiles and Pages as a source list;
     inspector becomes a trailing pane with grouped Form styling
   - Native toolbar: page add/remove, push-to-device, and appearance controls move
     into an NSToolbar-style SwiftUI toolbar with SF Symbols
   - Settings window (Cmd+comma): device options, brightness, sleep timer,
     launch at login toggle (SMAppService)
2. Controls and polish
   - Grouped Form sections with proper insets; footnote help text under fields
   - Tile grid gets hover states, selection animation, and drag to reorder
     (drag one tile onto another to swap; drag between pages via the sidebar)
   - Undo/redo support on profile edits (UndoManager)
   - Empty states and first-run onboarding card (connect device, grant Accessibility)
   - Consistent typography; SF Pro text styles instead of fixed point sizes
3. App identity
   - Menu bar dropdown gets connection details and quick page switching
   - About window with credits and the protocol war story
   - Optional: notch-style HUD confirmation when an action fires

Definition of done: side-by-side with System Settings, nothing looks foreign.

## Track 2: Connect choreography (the feedback Tim loves)

1. LED cascade on connect: sweep buttons 2 through 8 in a color wave right after
   the tile sweep finishes; doubles as a hardware self-test of every LED
2. Brightness fade-in on connect instead of a hard jump
3. Optional haptic tick when the device finishes loading a page
4. Same cascade runs on demand from the menu bar as "Test device"

## Track 3: Open source release

Model: Tim owns the repo and keeps committing to main exactly as now; the world
forks and sends pull requests; nothing about his workflow changes.

1. Repo prep
   - Name suggestion: RazerStream (org or personal repo); alternates: OpenLoupe, DeckKit
   - MIT license; README with screenshots, install steps, and the reverse
     engineering story; PROTOCOL.md documenting every hard-won byte
     (handshake newline, masked frames with zero key, 8N1, display ID 0x004D,
     brightness single byte, knob/button ID map, LED IDs, status light at ID 7)
   - CONTRIBUTING.md: build instructions, style rules (semicolons; no dashes),
     PR expectations; issue templates for bug/feature/device-report
   - .gitignore already present; add dist/ and .build/ if missing
2. Structure for contributors
   - Split RazerStreamKit into its own SPM package folder so other apps can
     depend on just the protocol layer; app depends on it by path
   - Tag v1.0.0; GitHub Release with a zipped notarizable app build
3. Workflow
   - Tim: push to main whenever; optionally a dev branch for experiments
   - Contributors: fork, branch, PR into main; Tim merges what he likes
   - GitHub Actions CI later: swift build and swift test on PRs
4. Prereq on this Mac: brew install gh; gh auth login; then one command setup

## Track 4: Features (post-polish)

1. App switching profiles: watch the frontmost app (NSWorkspace notifications)
   and auto-switch to a page or profile mapped to it; per-app mapping editor
   in Settings; manual override always wins
2. Profile import and export
   - Native: single .razerstream JSON file for sharing layouts (drag in, drag out)
   - Elgato Stream Deck: .streamDeckProfile is a zip of manifest JSON plus
     button images; map 15-key layouts onto our 12 tiles with a review step
   - Loupedeck 6.3: import what we can parse from local profile storage so
     refugees from the dead app keep their muscle memory
3. Icon libraries beyond SF Symbols
   - Bundle permissively licensed packs behind the same picker UI:
     Lucide (MIT), Tabler (MIT), Bootstrap Icons (MIT), Material Symbols
     (Apache 2.0), simple-icons for brand logos (CC0)
   - User icon packs: point the app at any folder of PNG/SVG files and it
     becomes a searchable library tab; this also covers Stream Deck icon packs
   - License text shipped with each bundled pack
4. Live tiles: clock, now playing with album art, CPU/RAM meter, calendar next-up;
   refresh loop redraws only dirty tiles
5. Haptics: vibrate patterns per action type (the hardware command already exists)
6. Touch gestures: two-finger swipe on the screen switches pages
7. Knob acceleration: fast turns scale the action (volume jumps by more)
8. Device sleep: dim after N minutes idle; wake on any input
9. Webhooks and Home Assistant/MQTT actions
10. Plugin API: action providers as separate processes or scripts

## Track 5: Other platforms (community owned)

Tim has no appetite to build these himself; the project is structured so
someone else can. PROTOCOL.md documents the full wire protocol precisely so a
port never needs a serial sniffer.

1. Linux kit and CLI: RazerStreamKit is Foundation plus POSIX serial I/O and
   compiles on Linux Swift with one small shim; replace the IOKit device
   discovery with a /dev/ttyACM* or sysfs scan behind #if os(Linux). The
   rstream CLI then ports nearly for free. Small, real, and a good first
   contribution.
2. Linux GUI: a new frontend (GTK or Qt) on top of the kit; contributors
   welcome.
3. Windows: realistically a C# app built against PROTOCOL.md; Swift on Windows
   exists but has no viable GUI story.

## Known environment notes

- macOS 27 beta CLT cannot compile SPM manifests; Xcode beta at /Applications
  works; this resolves itself when 27 ships stable
- Accessibility permission is tied to bundle identity; ad hoc signing means a
  fresh grant after significant rebuilds; a real Developer ID cert fixes that
- Device quirks live in PROTOCOL.md and in Claude's memory; the big ones:
  never write LED ID 7 (status light); pace framebuffer writes ~60ms;
  handshake requires the blank line
