import SwiftUI
import ServiceManagement

// Standard macOS Settings window (Cmd+comma). Grouped Form; HIG styling.

struct SettingsView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var brightness: Double = 8

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            device.tabItem { Label("Device", systemImage: "rectangle.grid.3x2") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 320)
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

    // MARK: About

    private var about: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("RazerStream").font(.title2.bold())
            Text("Version 2.0").foregroundStyle(.secondary)
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
