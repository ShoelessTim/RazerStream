import SwiftUI

@main
struct RazerStreamApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var deviceManager = DeviceManager()

    init() {
        setbuf(stdout, nil)   // immediate debug output when piped to a file
    }

    var body: some Scene {
        WindowGroup("RazerStream") {
            ContentView()
                .environmentObject(store)
                .environmentObject(deviceManager)
                .onAppear {
                    // Bare (non-bundled) binaries aren't foreground apps by
                    // default — promote ourselves so the window actually shows.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    deviceManager.start(store: store)
                }
        }

        MenuBarExtra {
            Text(deviceManager.connected
                 ? "Connected — fw \(deviceManager.firmware)"
                 : "No device")
            Divider()
            Button("Push Page to Device") {
                deviceManager.pushCurrentPage()
            }
            Button("Quit RazerStream") {
                deviceManager.stop()
                NSApplication.shared.terminate(nil)
            }
        } label: {
            // Live event readout directly in the menu bar
            HStack(spacing: 4) {
                Image(systemName: deviceManager.connected
                      ? "square.grid.3x2.fill" : "square.grid.3x2")
                Text(deviceManager.connected ? deviceManager.lastEvent : "—")
                    .font(.system(size: 11).monospaced())
            }
        }
    }
}
