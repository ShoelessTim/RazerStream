import SwiftUI

@main
struct RazerStreamApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var deviceManager = DeviceManager()

    var body: some Scene {
        WindowGroup("RazerStream") {
            ContentView()
                .environmentObject(store)
                .environmentObject(deviceManager)
                .onAppear {
                    deviceManager.start(store: store)
                }
        }

        MenuBarExtra("RazerStream", systemImage: "square.grid.3x2") {
            Text(deviceManager.connected ? "Device connected" : "No device")
            Divider()
            Button("Quit RazerStream") {
                deviceManager.stop()
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
