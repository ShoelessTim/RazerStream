# RazerStream V2 Roadmap

V1 status: shipped and hardware verified. Protocol library, pages, icon library,
behavior modes (tap / toggle / momentary / shift), keystroke recorder, media keys,
button LEDs, dark mode, installed app bundle. Faster than the Loupedeck app ever was.

Style rule for this repo: no double dashes and no em dashes in comments, docs,
or commit messages; join clauses with semicolons instead.

## Theme for V2

Two tracks: make it look and feel like a first-party Apple tool; make it a real
open source community project. Everything below is ordered; top items first.

## Track 1: Apple-native UI pass (HIG) — shipped

Goal: a stranger opens the app and assumes Apple shipped it.

- [x] NavigationSplitView, three columns: sidebar (pages, real list with
      double-click rename, drag to reorder, per-row delete), content (device
      mirror), detail (inspector); profiles deliberately deferred to the
      app-switching-profiles feature, which needs multi-profile UI anyway
- [x] Tile drag and drop, Home Screen icon shift semantics (not swap; verified
      against four cases including both directions and both boundaries)
- [x] Drag a tile onto a sidebar page row to move it to that page; only
      completes if the destination has a genuinely empty slot, so it can
      never silently overwrite existing configuration (verified: normal
      move, destination full, same-page drop)
- [x] Profile version history in place of undo/redo, matching Apple's own
      autosave-plus-versions model (File > Revert To > Browse All Versions):
      every save snapshots the state, Settings > History browses and
      restores, Duplicate Profile is the manual named checkpoint
- [x] Hover states (Dock-style magnify) and animated selection on tiles,
      knobs, and buttons; non-blocking banner when no device is connected
      (the mirror stays fully editable, since authoring offline is legitimate)
- [x] First-run onboarding sheet: plug in the device, grant Accessibility,
      both live-updating, shown once

Definition of done: side-by-side with System Settings, nothing looks foreign.
Not done in this pass, intentionally deferred: profile management UI (see
Track 4, app-switching profiles), native toolbar redesign, About window
polish, notch-style HUD confirmations.

## Track 2: Connect choreography (the feedback Tim loves) — shipped

1. [x] LED cascade on connect: sweep buttons 2 through 8 in a color wave right
   after the tile sweep finishes; doubles as a hardware self-test of every LED
2. [x] Brightness fade-in on connect instead of a hard jump (shipped v1.4.1)
3. Haptic tick when a page finishes loading. Shipped in v1.4.1, pulled in
   v1.4.2: it fired well after the page had already visibly finished
   drawing (only after the whole button-LED loop completed), which read as
   late and pointless rather than as confirmation. Not worth re-attempting
   without fixing the timing, and not a priority.
4. [x] Same cascade runs on demand from the menu bar as "Test device"

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
   - GitHub Actions CI: swift build and swift test on every push and PR (done)
4. Prereq on this Mac: brew install gh; gh auth login; then one command setup

## Track 4: Features (post-polish)

1. [x] App switching pages (shipped v1.2.0): watches the frontmost app via
   NSWorkspace activation notifications and switches to its mapped page;
   Settings > Apps has the mapping editor; a manual page change always
   sticks since nothing re-asserts the mapping until the next real app
   switch. Scoped to page-per-app within the current profile rather than a
   full profile switcher, matching what was actually needed.
2. Profile import and export
   - [x] Native: single .razerstream JSON file for sharing layouts, via
     Settings > History > Export/Import (shipped v1.4.1); not yet wired to
     Finder double-click-to-open, since that needs document-based app
     plumbing beyond what a Settings-panel export/import needed
   - Elgato Stream Deck: .streamDeckProfile is a zip of manifest JSON plus
     button images; map 15-key layouts onto our 12 tiles with a review step
   - Loupedeck 6.3: import what we can parse from local profile storage so
     refugees from the dead app keep their muscle memory
3. Icon libraries beyond SF Symbols (shipped in v1.1.0)
   - Bundled Lucide (MIT) and Bootstrap Icons (MIT); more packs are a copy
     into scripts/fetch_icon_packs.sh (Tabler, Material Symbols, simple-icons)
   - User icon packs: point the app at any folder of PNG/SVG files and it
     becomes a searchable library tab; this also covers Stream Deck icon packs
   - License text shipped with each bundled pack
4. Live tiles: [x] clock (shipped v1.1.0), [x] CPU/RAM meter (shipped
   v1.4.1; two bars on a tile, compact text on a knob strip, refreshes every
   2 seconds via the standard Mach host APIs, no private frameworks); still
   open: now playing with album art, calendar next-up; refresh loop redraws
   only dirty tiles
5. [x] Haptics: vibrate patterns per action type (shipped v1.4.0); fires on
   button/knob press and touch, plus a Settings > Haptics tab with a pattern
   picker and test button
6. Touch gestures: two-finger swipe on the screen switches pages. Shipped in
   v1.4.1, pulled in v1.4.2: the physical bezel ridges around the
   touchscreen make a real two-finger swipe an unpleasant gesture on this
   hardware, independent of the software (and the known limitation, that a
   swipe's starting touches could also fire whatever tile actions are under
   each finger, never got resolved either). Not worth revisiting unless the
   hardware ergonomics issue itself has a workaround.
7. [x] Knob acceleration: fast turns scale the action, volume/brightness step
   3x instead of 1x on quick consecutive turns (shipped v1.4.1)
8. [x] Device sleep: dim after N minutes idle, wake on any input; off by
   default, Settings > Device > "Dim after inactivity" (shipped v1.4.1).
   Extended in v1.4.2 to also dim the 7 configurable button LEDs (to ~12%
   of their configured color) alongside the screen, restoring both on the
   next input; the status light (button 7 / physical ID 7) is never
   touched by this app at all regardless of idle state, so it stays lit at
   its own device-managed brightness as a constant connection indicator.
9. Webhooks and Home Assistant/MQTT actions
10. Plugin API: action providers as separate processes or scripts. Concrete
    requirements from a real use case (r/loupedeck, u/Cuica, 2026-07-16; a
    Jellyfin media-player controller, migrating off a custom Loupedeck C#
    plugin):
    - Full-tile custom image drawing, not just label/icon/color config; a
      plugin needs to hand over an actual bitmap per redraw
    - High refresh rate for that custom content: an animated progress bar
      spanning four tiles plus a scrolling "now playing" title wants
      10 to 20fps, well past what a manual Apply-button edit needs
    - The same full-image drawing capability on knob zones, not just tiles;
      today's knob rendering (label + icon only) cannot do this at all
    - Two-way data, not just write: reading external state (Jellyfin's
      trickplay thumbnails for "next in queue") and writing it back (editing
      a star rating from the deck)
    - This all argues for a plugin being handed a raw pixel buffer per
      button/knob zone on some interval, plus a channel to receive input
      events back, rather than the current declarative TileConfig/KnobConfig
      shape; a real design decision to make when this gets picked up, not
      solved here

## Community requests (r/loupedeck, v1.0 launch thread, 2026-07-16/17)

1. Loupedeck CT support (u/c3p00). A different physical device from the
   Razer Stream Controller this app targets (which is a rebranded Loupedeck
   Live); CT has its own screen/button/dial layout and likely its own
   protocol quirks. Not scoped or investigated at all yet; would need a
   serial capture from an actual CT owner before anything concrete could be
   said about feasibility.
2. Can you run this without uninstalling the original Loupedeck software
   first? (u/Lewd_Toaster). Real open question, told them "i havent tested
   that yet" in the thread. The known conflict so far is the old Loupedeck
   app/LaunchAgent grabbing the serial port if it's running (see
   razerstream-protocol-notes memory); untested whether just quitting it is
   enough or a full uninstall is required, and whether either leaves any
   state that fights RazerStream. Worth an explicit test and a README/FAQ
   note once answered, since it's clearly a common worry for people coming
   from the dead app.
3. From a v1.4.0 installer, filed as GitHub issues plus direct feedback
   (2026-07-18):
   - More knob rotation presets: mouse vertical/horizontal scroll, and a
     click action for knob press specifically tied to scrolling (distinct
     from the general-purpose press action that already exists). Would
     slot into the same KnobRotationMode picker as Volume/Brightness/Page
     Nav/Track.
   - LED button brightness as a knob rotation preset (turn a knob to dim
     the 7 configurable button LEDs directly, not just tied to idle
     dimming). Idle-tied dimming shipped in v1.4.2 (see below); a
     manually-adjustable version is still open.
   - Multi-action macros: fire a sequence of ControlActions from one tap,
     not just a single action. Called out as "a must" to be a viable
     Loupedeck replacement. Real scope decision needed: a new
     `.sequence([ControlAction])` case is the obvious shape, but delays
     between steps, and what happens if one step fails, need actual design
     thought before building.
   - Default/application profiles with their own pages, replacing
     page-switching as the way "mapped apps" work: instead of one profile
     with app-switching mapping bundle IDs to pages within it, each app
     would get its own full profile. Overlaps with Track 4 item 1
     (app-switching pages, already shipped) and the deferred Track 1
     profile-management UI; whether to extend the existing page-per-app
     model or actually add profile-per-app is a real design fork, not
     picked yet.
   - Context, from the same feedback: "Logitech and Loupedeck are getting
     more aggressive blocking this device... if you have Logi Options+
     installed" — worth keeping in mind for the open uninstall-coexistence
     question above; may not be a RazerStream-side fix at all if it's
     Logi Options+ actively interfering rather than just port contention.

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
