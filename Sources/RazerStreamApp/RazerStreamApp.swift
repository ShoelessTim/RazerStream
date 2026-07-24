import SwiftUI

// Bridge so non-SwiftUI code (a device button firing the Show action) can ask
// the app to open or front the main window. The closure is captured once at
// launch from a SwiftUI context that has openWindow.
@MainActor
final class AppActions {
    static let shared = AppActions()
    var showMainWindow: (() -> Void)?
    // The window's onAppear fires every time it opens, not just at launch;
    // this gates the launch-time "start hidden in the menu bar" behavior so
    // a later manual reopen always shows the window normally.
    var didHandleLaunch = false
}

@main
struct RazerStreamApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var deviceManager = DeviceManager()
    @StateObject private var packManager = IconPackManager()

    // 0 = follow system (default), 1 = light, 2 = dark
    @AppStorage("appearanceMode") private var appearanceMode = 0

    // When set, launch straight to the menu bar (no window, no Dock icon)
    // instead of opening the control window.
    @AppStorage("launchInMenuBar") private var launchInMenuBar = false

    init() {
        setbuf(stdout, nil)   // immediate debug output when piped to a file
    }

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case 1:  return .light
        case 2:  return .dark
        default: return nil   // system
        }
    }

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Single Window (not WindowGroup); openWindow fronts the existing one
        // or reopens it if closed, and never spawns a duplicate. That is the
        // right model for a control panel.
        Window("RazerStream", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(deviceManager)
                .environmentObject(packManager)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    deviceManager.start(store: store)
                    // Capture a reopen closure for non-SwiftUI callers; always
                    // promotes back to a normal windowed app, so "Show
                    // RazerStream" works even when we launched menu-bar-only.
                    AppActions.shared.showMainWindow = {
                        NSApp.setActivationPolicy(.regular)
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }

                    // onAppear also fires on every later reopen; only the very
                    // first pass is "launch", and only then do we honor the
                    // start-hidden preference.
                    if AppActions.shared.didHandleLaunch {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        return
                    }
                    AppActions.shared.didHandleLaunch = true

                    if launchInMenuBar {
                        // Live only in the menu bar: no Dock icon, no app menus,
                        // and close the window this scene just opened.
                        NSApp.setActivationPolicy(.accessory)
                        DispatchQueue.main.async {
                            NSApp.windows.first {
                                ($0.identifier?.rawValue.contains("main") ?? false)
                                    || $0.title == "RazerStream"
                            }?.close()
                        }
                    } else {
                        // Bare binaries aren't foreground apps by default;
                        // promote ourselves so the window actually shows.
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .commands {
            CommandMenu("Device") {
                Button("Show RazerStream") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Test Device (LED Sweep)") {
                    deviceManager.testDevice()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!deviceManager.connected)

                Button("Redraw Page on Device") {
                    deviceManager.pushCurrentPage()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!deviceManager.connected)
            }

            CommandGroup(replacing: .help) {
                Button("RazerStream Help") { openWindow(id: "help") }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("RazerStream Help", id: "help") {
            HelpView()
                .preferredColorScheme(colorScheme)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(deviceManager)
                .environmentObject(packManager)
                .preferredColorScheme(colorScheme)
        }

        MenuBarExtra {
            Text(deviceManager.connected
                 ? "Connected — fw \(deviceManager.firmware)"
                 : "No device")
            Divider()
            Picker("Appearance", selection: $appearanceMode) {
                Text("System").tag(0)
                Text("Light").tag(1)
                Text("Dark").tag(2)
            }
            Divider()
            Button("Show RazerStream") {
                AppActions.shared.showMainWindow?()
            }
            // Reachable even when launched menu-bar-only (no app menus, so
            // Cmd-comma isn't available until the window is shown).
            SettingsLink {
                Text("Settings…")
            }
            Button("Test Device (LED sweep)") {
                deviceManager.testDevice()
            }
            .disabled(!deviceManager.connected)
            Button("Push Page to Device") {
                deviceManager.pushCurrentPage()
            }
            Button("Quit RazerStream") {
                deviceManager.stop()
                NSApplication.shared.terminate(nil)
            }
        } label: {
            // Icon only; the live readout lives in the window status bar
            Image(nsImage: DeckIcon.menuBar)
        }
    }
}
