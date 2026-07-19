import SwiftUI

// In-app user guide; opened from the Help menu or Cmd+?
// Content is hand-built SwiftUI so it renders nicely in light and dark mode.

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section("Getting Started", icon: "power") {
                    step(1, "Plug in your Razer Stream Controller over USB.")
                    step(2, "Launch RazerStream; the status bar dot turns green when connected.")
                    step(3, "The window mirrors your device: 12 tiles, 6 knobs, 8 round buttons.")
                    note("The old Loupedeck software must not be running; it holds the device hostage. Quit it or uninstall it.")
                }

                section("Tiles", icon: "square.grid.3x2.fill") {
                    bullet("Click any tile in the window to edit it.")
                    bullet("Label: text drawn on the tile; Background: any color via the Apple color panel (the crayons live in the last tab).")
                    bullet("Icon Library: searchable built-in icons; type any SF Symbol name for the full Apple catalog.")
                    bullet("Custom image: choose any PNG or JPEG; it wins over the icon.")
                    bullet("Press Apply; the device redraws instantly.")
                }

                section("Knobs", icon: "dial.medium") {
                    bullet("Knobs live in the two side columns; K0 to K2 on the left, K3 to K5 on the right, top to bottom.")
                    bullet("Each knob has three actions: turn right, turn left, and press.")
                    bullet("A knob's label and icon draw on the screen strip next to it.")
                    tip("Classic setup: volume up on right turn, volume down on left turn, mute on press.")
                }

                section("Physical Buttons", icon: "circle.grid.2x1.fill") {
                    bullet("The eight round buttons under the screen; click one in the window to assign its action.")
                    bullet("Buttons 2 through 8 have color LEDs; pick a color in the editor.")
                    bullet("Button 1's LED is the device status light; the device controls it, not us.")
                }

                section("Behaviors", icon: "arrow.triangle.2.circlepath") {
                    labeled("Tap", "fires the action once on press; the default.")
                    labeled("Toggle", "alternates between an ON action and an OFF action; the tile can swap to a different icon while ON and shows a white ring; a button's LED lights while ON.")
                    labeled("Momentary", "one action on press, another on release; hold-to-talk style.")
                    labeled("Shift", "hold to show a different page on the device; release snaps back. Pages become layers.")
                    tip("Play/Pause recipe: Toggle mode; both actions set to Play / Pause; icon play.fill; icon when ON pause.fill.")
                }

                section("Pages", icon: "square.on.square") {
                    bullet("Pages are full layouts; switch with the tabs above the grid.")
                    bullet("Plus adds a page; the trash icon deletes the current one.")
                    bullet("Any control can jump pages: Go to Page, Next Page, Previous Page actions.")
                }

                section("Actions", icon: "bolt.fill") {
                    labeled("Open App", "launches any application.")
                    labeled("Shell Command", "runs a zsh one-liner.")
                    labeled("AppleScript", "runs a script; volume actions use this under the hood.")
                    labeled("Keystroke", "click the recorder, press the real keys, done; one chord per step (⌘⇧K), not a long typing stream.")
                    labeled("Macro", "several actions in order, with an optional wait after each step; use this for multi-keystroke sequences (⌘C, wait, ⌘V) or open-app-then-keys. Empty steps are skipped.")
                    labeled("Media keys", "Play / Pause, Next Track, Previous Track; these control Music, Spotify, browsers, anything that answers the keyboard media keys.")
                    labeled("Volume", "up, down, and mute toggle.")
                }

                section("Permissions", icon: "lock.shield") {
                    bullet("Keystrokes and media keys need the macOS Accessibility permission.")
                    bullet("When it's missing, an orange chip appears in the status bar; click it to open the right Settings pane.")
                    important("After updating the app you may need to re-grant: in System Settings, Privacy and Security, Accessibility, remove RazerStream with the minus button, then re-add it from /Applications. This is a macOS rule about app signatures, not a bug.")
                }

                section("Troubleshooting", icon: "wrench.and.screwdriver.fill") {
                    labeled("Device screen blank", "unplug the USB cable, wait two seconds, plug back in; the app reconnects on its own within a few seconds.")
                    labeled("No connection", "check that the old Loupedeck app is not running; it grabs the port.")
                    labeled("Volume works but keystrokes don't", "that's the Accessibility grant; see Permissions above.")
                    labeled("Tiles look dim", "brightness is per profile; it restores on every connect.")
                    labeled("Pack icons missing after relaunch", "fixed in 1.5.1; bundled icons are stored as stable IconPacks/… paths instead of a temporary app location. Open the app once to rewrite an old profile, or re-pick the icon.")
                }

                footer
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(minWidth: 560, idealWidth: 660, minHeight: 500, idealHeight: 640)
    }

    // MARK: layout pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RazerStream Help")
                .font(.largeTitle.bold())
            Text("A community replacement for the retired Loupedeck software; built for the Razer Stream Controller.")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text("RazerStream is an open community project; it is not affiliated with Razer, Loupedeck, or Logitech.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func section(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(.leading, 2)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").bold().foregroundStyle(.secondary)
            Text(text)
        }
    }

    private func labeled(_ term: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(term).bold()
            Text(text).foregroundStyle(.primary)
        }
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "lightbulb.fill")
            .foregroundStyle(.secondary)
            .font(.callout)
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle.fill")
            .foregroundStyle(.secondary)
            .font(.callout)
    }

    private func important(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.callout)
    }
}
