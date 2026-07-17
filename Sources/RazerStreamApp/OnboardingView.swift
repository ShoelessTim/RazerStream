import SwiftUI

// First-run welcome sheet: walks through the two things a fresh install
// needs (plug in the device, grant Accessibility) and live-updates as each
// becomes true. Shown once; ContentView gates it on hasCompletedOnboarding.

struct OnboardingView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @Environment(\.dismiss) private var dismiss

    @State private var axGranted = ActionEngine.hasAccessibility
    private let axTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 6) {
                Text("Welcome to RazerStream")
                    .font(.title2.bold())
                Text("A couple of quick things to get your deck fully working.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                step(
                    done: deviceManager.connected,
                    title: "Plug in your Razer Stream Controller",
                    subtitle: deviceManager.connected ? "Connected" : "Waiting for the device…"
                ) { EmptyView() }

                step(
                    done: axGranted,
                    title: "Grant Accessibility permission",
                    subtitle: axGranted ? "Granted" : "Needed for keystrokes and media key actions"
                ) {
                    if !axGranted {
                        Button("Grant…") {
                            ActionEngine.requestAccessibility()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Get Started") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(30)
        .frame(width: 420)
        .onReceive(axTimer) { _ in axGranted = ActionEngine.hasAccessibility }
    }

    @ViewBuilder
    private func step<Trailing: View>(
        done: Bool, title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
    }
}
