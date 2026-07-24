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
                // Runs the once-at-launch setup from inside the window's view
                // hierarchy, early enough (viewDidMoveToWindow) to order the
                // window out before it's ever drawn when launching menu-bar
                // only; that pre-empts the on-screen flash that closing it
                // after onAppear caused.
                .background(LaunchConfigurator(hideAtLaunch: launchInMenuBar) {
                    deviceManager.start(store: store)
                    AppActions.shared.showMainWindow = {
                        NSApp.setActivationPolicy(.regular)
                        openWindow(id: "main")
                        if let w = Self.mainWindow {
                            w.alphaValue = 1   // undo the launch-time hide, if any
                            w.makeKeyAndOrderFront(nil)
                        }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                })
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
            // Icon only; the live readout lives in the window status bar.
            // The MenuBarExtra label is present from the moment the app
            // launches, whether or not the main window is suppressed, so its
            // onAppear is the reliable once-at-launch hook: start the device,
            // wire the reopen closure, and drop the Dock icon when running
            // menu-bar-only. (The window's own onAppear can't do this job
            // because a suppressed window never appears.)
            Image(nsImage: DeckIcon.menuBar)
        }
    }

    // The main control window, for showMainWindow to force visible after a
    // menu-bar-only launch left it ordered out.
    @MainActor
    static var mainWindow: NSWindow? {
        NSApp.windows.first {
            ($0.identifier?.rawValue.contains("main") ?? false) || $0.title == "RazerStream"
        }
    }
}

// Runs once-at-launch setup from inside the window's AppKit view hierarchy.
// viewDidMoveToWindow fires while the window is being assembled, before it's
// ordered on screen, so ordering it out there (when launching menu-bar only)
// pre-empts the draw instead of flashing a window and closing it a runloop
// later. A plain view with no visible content; it exists only for the hook.
private struct LaunchConfigurator: NSViewRepresentable {
    let hideAtLaunch: Bool
    let onLaunch: () -> Void

    func makeNSView(context: Context) -> NSView {
        LaunchConfigView(hideAtLaunch: hideAtLaunch, onLaunch: onLaunch)
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class LaunchConfigView: NSView {
    private let hideAtLaunch: Bool
    private let onLaunch: () -> Void

    init(hideAtLaunch: Bool, onLaunch: @escaping () -> Void) {
        self.hideAtLaunch = hideAtLaunch
        self.onLaunch = onLaunch
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Only the first window mount is "launch"; a later Show reuses the
        // same window, so this doesn't fire again and can't re-hide it.
        guard let window, !AppActions.shared.didHandleLaunch else { return }
        AppActions.shared.didHandleLaunch = true

        onLaunch()

        if hideAtLaunch {
            // Menu-bar-only: no Dock icon, and out before it's ever drawn.
            // alphaValue 0 is belt-and-suspenders: if SwiftUI still orders the
            // window front after this during its own launch pass, it stays
            // invisible rather than flashing; showMainWindow restores it to 1.
            NSApp.setActivationPolicy(.accessory)
            window.alphaValue = 0
            window.orderOut(nil)
        } else {
            // Bare binaries aren't foreground apps by default; promote so the
            // window and its menus show.
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
