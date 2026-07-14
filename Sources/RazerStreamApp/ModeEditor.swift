import SwiftUI

// Reusable behavior-mode section: Tap / Toggle / Momentary / Shift,
// with the right secondary editors for each mode.

struct ModeEditor: View {
    @Binding var mode: ControlMode
    @Binding var action: ControlAction
    @Binding var releaseAction: ControlAction
    /// Non-nil enables the toggle "icon when on" picker (tiles only)
    var altSymbol: Binding<String>?

    @EnvironmentObject var store: ProfileStore
    @State private var kind: Kind = .tap
    @State private var shiftTarget = 0
    @State private var showAltPicker = false

    enum Kind: String, CaseIterable {
        case tap = "Tap"
        case toggle = "Toggle (on/off)"
        case momentary = "Momentary (hold)"
        case shift = "Shift (hold for page)"
    }

    var body: some View {
        Picker("Behavior", selection: $kind) {
            ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
        }
        .onChange(of: kind) { syncOut() }

        switch kind {
        case .tap:
            ActionEditor(title: "On tap", action: $action)

        case .toggle:
            ActionEditor(title: "Turning ON", action: $action)
            ActionEditor(title: "Turning OFF", action: $releaseAction)
            if let altSymbol {
                HStack {
                    Text("Icon when ON").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !altSymbol.wrappedValue.isEmpty {
                        Image(systemName: altSymbol.wrappedValue)
                    }
                    Button("Choose…") { showAltPicker = true }
                }
                .sheet(isPresented: $showAltPicker) {
                    SymbolPicker(symbol: altSymbol)
                }
            }

        case .momentary:
            ActionEditor(title: "On press", action: $action)
            ActionEditor(title: "On release", action: $releaseAction)

        case .shift:
            Picker("Hold to show", selection: $shiftTarget) {
                ForEach(0..<store.activeProfile.pages.count, id: \.self) { i in
                    Text(store.activeProfile.pages[i].name).tag(i)
                }
            }
            .onChange(of: shiftTarget) { syncOut() }
            Text("Device shows that page while held, snaps back on release.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // keep bindings in sync when parent reloads
        Color.clear.frame(height: 0)
            .onAppear(perform: syncIn)
            .onChange(of: mode) { syncIn() }
    }

    private func syncIn() {
        switch mode {
        case .tap:                 kind = .tap
        case .toggle:              kind = .toggle
        case .momentary:           kind = .momentary
        case .shiftPage(let p):    kind = .shift; shiftTarget = p
        }
    }

    private func syncOut() {
        switch kind {
        case .tap:       mode = .tap
        case .toggle:    mode = .toggle
        case .momentary: mode = .momentary
        case .shift:     mode = .shiftPage(shiftTarget)
        }
    }
}
