import SwiftUI
import ServiceManagement
import RazerStreamKit
import UniformTypeIdentifiers

// Standard macOS Settings window (Cmd+comma). Grouped Form; HIG styling.

// Wraps one Profile's JSON for the standard SwiftUI file exporter; a plain
// data pass-through rather than encoding/decoding a whole Profile inline
// here, so the file format stays exactly what ProfileStore already reads
// and writes for the main profiles.json store.
struct ProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.razerStreamProfile] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var brightness: Double = 8
    @State private var ledBrightness: Double = 10
    @State private var hapticsEnabled = HapticFeedback.isEnabled
    @State private var hapticPattern = HapticFeedback.pattern
    @State private var clockwiseIncreases = KnobDirection.clockwiseIncreases
    @State private var idleDimmingEnabled = IdleDimming.isEnabled
    @State private var idleDimmingMinutes = IdleDimming.minutes

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
                    deviceManager.pushBrightness()
                }
            }

            Section {
                HStack {
                    Image(systemName: "circle.dotted")
                    Slider(value: $ledBrightness, in: 0...10, step: 1)
                    Image(systemName: "circle.fill")
                }
                .onChange(of: ledBrightness) { _, v in
                    store.updateActive { $0.ledBrightness = UInt8(v) }
                    deviceManager.pushBrightness()
                }
            } header: {
                Text("Button LEDs")
            } footer: {
                Text("Also assignable to a knob (Rotation > Button LED Brightness). The status light isn't affected either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Turning right (clockwise)", selection: $clockwiseIncreases) {
                    Text("Increases").tag(true)
                    Text("Decreases").tag(false)
                }
                .onChange(of: clockwiseIncreases) { _, v in
                    KnobDirection.clockwiseIncreases = v
                    store.reapplyKnobDirection()
                    deviceManager.pushCurrentPage()
                }
            } footer: {
                Text("Applies to every knob set to Volume, Brightness, Page Navigation, Track, or Mouse Scroll rotation, on every page and profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Dim after inactivity", isOn: $idleDimmingEnabled)
                    .onChange(of: idleDimmingEnabled) { _, v in IdleDimming.isEnabled = v }
                if idleDimmingEnabled {
                    Picker("Dim after", selection: $idleDimmingMinutes) {
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("30 minutes").tag(30)
                    }
                    .onChange(of: idleDimmingMinutes) { _, v in IdleDimming.minutes = v }
                }
            } footer: {
                Text("Dims the panel and button LEDs after no button, knob, or touch input; any input wakes them back up. The status light is never dimmed, so connection state always stays visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .onAppear {
            brightness = Double(store.activeProfile.brightness)
            ledBrightness = Double(store.activeProfile.ledBrightness)
            clockwiseIncreases = KnobDirection.clockwiseIncreases
            idleDimmingEnabled = IdleDimming.isEnabled
            idleDimmingMinutes = IdleDimming.minutes
        }
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
    @State private var exportDocument: ProfileDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importFailed = false

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
                Button {
                    guard let data = store.exportData(for: store.activeProfile.id) else { return }
                    exportDocument = ProfileDocument(data: data)
                    showExporter = true
                } label: {
                    Label("Export Current Profile…", systemImage: "square.and.arrow.up")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import Profile…", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Saves or loads a single profile as a standalone .razerstream file, to share a layout or back one up outside the app.")
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
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .razerStreamProfile,
            defaultFilename: store.activeProfile.name
        ) { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.razerStreamProfile]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    importFailed = !store.importProfile(from: data)
                } else {
                    importFailed = true
                }
            case .failure:
                importFailed = true
            }
        }
        .alert("Couldn't Import Profile", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That file doesn't look like a valid RazerStream profile.")
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
