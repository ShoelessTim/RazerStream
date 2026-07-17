import SwiftUI
import ServiceManagement
import RazerStreamKit

// Standard macOS Settings window (Cmd+comma). Grouped Form; HIG styling.

struct SettingsView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var brightness: Double = 8
    @State private var hapticsEnabled = HapticFeedback.isEnabled
    @State private var hapticPattern = HapticFeedback.pattern

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            device.tabItem { Label("Device", systemImage: "rectangle.grid.3x2") }
            haptics.tabItem { Label("Haptics", systemImage: "waveform") }
            apps.tabItem { Label("Apps", systemImage: "square.stack.3d.up") }
            icons.tabItem { Label("Icons", systemImage: "photo.on.rectangle.angled") }
            history.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }

    // MARK: General

    private var general: some View {
        Form {
            Picker("Appearance", selection: $appearanceMode) {
                Text("System").tag(0)
                Text("Light").tag(1)
                Text("Dark").tag(2)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { LaunchAtLogin.set($1) }

            Section {
                if ActionEngine.hasAccessibility {
                    Label("Accessibility granted; keystrokes and media keys work",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Label("Accessibility not granted", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant…") {
                            ActionEngine.requestAccessibility()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Device

    private var device: some View {
        Form {
            LabeledContent("Status") {
                Label(deviceManager.connected ? "Connected" : "Disconnected",
                      systemImage: deviceManager.connected ? "circle.fill" : "circle")
                    .foregroundStyle(deviceManager.connected ? .green : .secondary)
            }
            LabeledContent("Firmware", value: deviceManager.firmware)
            LabeledContent("Serial", value: deviceManager.serial)

            Section("Display") {
                HStack {
                    Image(systemName: "sun.min")
                    Slider(value: $brightness, in: 0...10, step: 1)
                    Image(systemName: "sun.max")
                }
                .onChange(of: brightness) { _, v in
                    store.updateActive { $0.brightness = UInt8(v) }
                    deviceManager.pushCurrentPage()
                }
            }

            Section {
                Button {
                    deviceManager.testDevice()
                } label: {
                    Label("Test Device (LED sweep)", systemImage: "wand.and.rays")
                }
                .disabled(!deviceManager.connected)
            }
        }
        .formStyle(.grouped)
        .onAppear { brightness = Double(store.activeProfile.brightness) }
    }

    // MARK: Icons

    @EnvironmentObject var packManager: IconPackManager

    private var icons: some View {
        Form {
            Section("Icon packs") {
                ForEach(packManager.packs) { pack in
                    LabeledContent(pack.name) {
                        Text("\(pack.icons.count) icons")
                            .foregroundStyle(.secondary)
                        if packManager.userFolders.contains(pack.directory.path) {
                            Button {
                                packManager.removeUserFolder(pack.directory.path)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Remove this folder")
                        }
                    }
                }
                if packManager.packs.isEmpty {
                    Text("No icon packs found")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.prompt = "Add Folder"
                    if panel.runModal() == .OK, let url = panel.url {
                        packManager.addUserFolder(url)
                    }
                } label: {
                    Label("Add a folder of icons…", systemImage: "folder.badge.plus")
                }
            } footer: {
                Text("Any folder of PNG or SVG files becomes a searchable tab in the icon library; Stream Deck icon packs work as is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Haptics

    private var haptics: some View {
        Form {
            Toggle("Vibrate on button and touch presses", isOn: $hapticsEnabled)
                .onChange(of: hapticsEnabled) { HapticFeedback.isEnabled = $1 }

            Section {
                Picker("Pattern", selection: $hapticPattern) {
                    Text("Short").tag(Haptic.short)
                    Text("Medium").tag(Haptic.medium)
                    Text("Long").tag(Haptic.long)
                    Text("Very Long").tag(Haptic.veryLong)
                    Text("Buzz").tag(Haptic.buzz)
                    Text("Rumble 1").tag(Haptic.rumble1)
                    Text("Rumble 2").tag(Haptic.rumble2)
                    Text("Rise and Fall").tag(Haptic.riseFall)
                }
                .disabled(!hapticsEnabled)
                .onChange(of: hapticPattern) { HapticFeedback.pattern = $1 }

                Button("Test") {
                    deviceManager.testHaptic(hapticPattern)
                }
                .disabled(!hapticsEnabled || !deviceManager.connected)
            } footer: {
                Text("Fires once whenever you press a physical button, a knob, or tap the touchscreen; not while turning a knob.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Apps

    private var apps: some View {
        Form {
            Toggle("Switch pages automatically based on the frontmost app",
                   isOn: Binding(
                    get: { store.activeProfile.appSwitchingEnabled },
                    set: { store.setAppSwitchingEnabled($0) }
                   ))

            Section {
                let mappings = Array(store.activeProfile.appPageMappings).sorted { $0.key < $1.key }
                if mappings.isEmpty {
                    Text("No apps mapped yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mappings, id: \.key) { bundleID, pageIDString in
                        AppMappingRow(bundleID: bundleID, pageIDString: pageIDString)
                    }
                }
            } header: {
                Text("Mapped Apps")
            } footer: {
                Text("A manual page change always wins; RazerStream only switches when a different app becomes frontmost, so it never fights you while you are working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK, let url = panel.url,
                       let bundleID = Bundle(url: url)?.bundleIdentifier {
                        // New mappings default to the page you are looking at
                        // right now; the row's own picker changes it after.
                        store.setAppMapping(bundleID: bundleID, pageID: store.currentPage.id)
                    }
                } label: {
                    Label("Add App…", systemImage: "plus.app")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: History

    @State private var versionToRestore: ProfileStore.ProfileVersion?

    private var history: some View {
        Form {
            Section {
                Button {
                    store.duplicateProfile(store.activeProfile.id)
                } label: {
                    Label("Duplicate Current Profile", systemImage: "plus.square.on.square")
                }
            } footer: {
                Text("Makes a named copy you can keep as a checkpoint; edits to the original will not affect it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                let versions = store.listVersions()
                if versions.isEmpty {
                    Text("No saved versions yet")
                        .foregroundStyle(.secondary)
                } else {
                    List(versions.prefix(20)) { version in
                        LabeledContent {
                            Button("Restore") { versionToRestore = version }
                                .font(.caption)
                        } label: {
                            Text(version.date, format: .dateTime.month().day().hour().minute().second())
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 200)
                }
            } header: {
                Text("Previous Versions")
            } footer: {
                Text("RazerStream saves a snapshot every time you apply a change; restoring one becomes a new save point, so nothing already saved is ever lost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Restore this version?",
            isPresented: Binding(get: { versionToRestore != nil }, set: { if !$0 { versionToRestore = nil } }),
            presenting: versionToRestore
        ) { version in
            Button("Restore", role: .destructive) {
                store.restoreVersion(version)
                deviceManager.pushCurrentPage()
            }
        } message: { version in
            Text("Replaces all profiles and pages with the version saved at \(version.date.formatted(date: .abbreviated, time: .standard)). The current state is saved first, so you can restore back to it afterward.")
        }
    }

    // MARK: About

    private var about: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("RazerStream").font(.title2.bold())
            Text("Version \(ContentView.appVersion)").foregroundStyle(.secondary)
            Text("A community replacement for the retired Loupedeck software.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Not affiliated with Razer, Loupedeck, or Logitech.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - App mapping row

private struct AppMappingRow: View {
    @EnvironmentObject var store: ProfileStore
    let bundleID: String
    let pageIDString: String

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private var appName: String {
        guard let url = appURL else { return bundleID }
        return (url.lastPathComponent as NSString).deletingPathExtension
    }

    private var appIcon: NSImage {
        guard let url = appURL else { return NSWorkspace.shared.icon(for: .application) }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 20, height: 20)
            Text(appName)
                .lineLimit(1)

            Spacer(minLength: 8)

            Picker("", selection: Binding(
                get: { pageIDString },
                set: { newID in
                    if let uuid = UUID(uuidString: newID) {
                        store.setAppMapping(bundleID: bundleID, pageID: uuid)
                    }
                }
            )) {
                ForEach(store.activeProfile.pages) { page in
                    Text(page.name).tag(page.id.uuidString)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 140)

            Button {
                store.removeAppMapping(bundleID: bundleID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
    }
}

// MARK: - Launch at login (SMAppService)

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LaunchAtLogin toggle failed: \(error)")
        }
    }
}
