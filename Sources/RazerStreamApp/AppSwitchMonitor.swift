import AppKit

// Watches which app is frontmost and switches the device to that app's
// mapped page. Only reacts to real activation events (not a poll), so a
// manual page change the user makes while an app stays frontmost is never
// immediately overridden; it sticks until the next actual app switch.

@MainActor
final class AppSwitchMonitor {
    private var observer: NSObjectProtocol?
    private weak var store: ProfileStore?
    private weak var deviceManager: DeviceManager?

    func start(store: ProfileStore, deviceManager: DeviceManager) {
        self.store = store
        self.deviceManager = deviceManager
        // Notification and NSRunningApplication are not Sendable, so pull out
        // just the bundle identifier before crossing onto the main actor;
        // that is the only piece handleActivation actually needs.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier
            else { return }
            Task { @MainActor [weak self] in
                self?.handleActivation(bundleID: bundleID)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func handleActivation(bundleID: String) {
        guard let store, let deviceManager else { return }
        guard let pageIndex = store.pageIndex(forBundleID: bundleID),
              pageIndex != store.currentPageIndex
        else { return }
        store.goToPage(pageIndex)
        deviceManager.pushCurrentPage()
    }
}
