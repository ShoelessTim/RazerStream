import SwiftUI

// Picking a button LED colour, with the physical button as the preview.
//
// A bare ColorPicker swatch is a poor fit for this job. It offers the full
// colour space when an RGB LED really only does a handful of colours
// convincingly; it gives no hint that black means off; and you cannot tell
// what you picked until you apply it and look down at the deck. Worse, the
// swatch shows the raw colour while the LED shows that colour scaled by the
// profile's LED brightness, so the two rarely match.
//
// So: named presets for the common cases, an explicit Off, the full picker
// still there for anything else, and every change lit on the real button
// straight away.

struct LEDColorPicker: View {
    @Binding var hex: String
    /// Physical button index; 0 is the status light and is never offered here.
    let buttonIndex: Int

    @EnvironmentObject var deviceManager: DeviceManager

    /// Saturated colours, which is what actually reads well on a small RGB
    /// LED; muted and pastel shades tend to come out looking like a dim white.
    private static let presets: [(name: String, hex: String)] = [
        ("Red",     "FF0000"),
        ("Orange",  "FF6A00"),
        ("Yellow",  "FFD400"),
        ("Green",   "00FF2A"),
        ("Mint",    "00FFA3"),
        ("Cyan",    "00E5FF"),
        ("Blue",    "0066FF"),
        ("Purple",  "9D00FF"),
        ("Magenta", "FF00C8"),
        ("Pink",    "FF6FA5"),
        ("White",   "FFFFFF"),
    ]

    private var isOff: Bool { hex.uppercased() == "000000" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LED colour")
                Spacer()
                Text(isOff ? "Off" : "#\(hex.uppercased())")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.adaptive(minimum: 30), spacing: 6), count: 6),
                      spacing: 6) {
                offSwatch
                ForEach(Self.presets, id: \.hex) { preset in
                    swatch(preset.hex, name: preset.name)
                }
            }

            HStack {
                ColorPicker("Custom…", selection: Binding(
                    get: { Color(hex: hex) },
                    set: { apply($0.hexString) }
                ), supportsOpacity: false)
                .labelsHidden()
                Text("Custom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(deviceManager.connected
                 ? "The button lights up as you pick, so you can see the real colour."
                 : "Connect the deck to preview colours on the button itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var offSwatch: some View {
        Button {
            apply("000000")
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.55))
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isOff ? Color.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: isOff ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help("Off")
    }

    private func swatch(_ value: String, name: String) -> some View {
        let selected = hex.uppercased() == value.uppercased()
        return Button {
            apply(value)
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: value))
                .frame(height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Color.accentColor : Color.black.opacity(0.25),
                                lineWidth: selected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .help(name)
    }

    /// Sets the colour and lights the real button immediately. The preview is
    /// only a preview: nothing is saved until the inspector's Apply, and the
    /// next page push restores whatever is actually stored.
    private func apply(_ value: String) {
        hex = value
        deviceManager.previewButtonLED(buttonIndex, hex: value)
    }
}
