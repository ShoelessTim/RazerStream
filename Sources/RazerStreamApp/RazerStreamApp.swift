import SwiftUI

@main
struct RazerStreamApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var deviceManager = DeviceManager()

    // 0 = follow system (default), 1 = light, 2 = dark
    @AppStorage("appearanceMode") private var appearanceMode = 0

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
        WindowGroup("RazerStream") {
            ContentView()
                .environmentObject(store)
                .environmentObject(deviceManager)
                .preferredColorScheme(colorScheme)
                .onAppear {
                    // Bare binaries aren't foreground apps by default;
                    // promote ourselves so the window actually shows
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    deviceManager.start(store: store)
                }
        }
        .commands {
            CommandMenu("Device") {
                Button("Show RazerStream") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let w = NSApp.windows.first(where: { $0.title == "RazerStream" }) {
                        w.makeKeyAndOrderFront(nil)
                    }
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
                NSApp.activate(ignoringOtherApps: true)
                if let w = NSApp.windows.first(where: { $0.title == "RazerStream" }) {
                    w.makeKeyAndOrderFront(nil)
                }
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
