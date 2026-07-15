import SwiftUI

// The full icon browser: System tab (SF Symbols) plus one tab per icon pack.
// Picking a symbol sets `symbol` and clears `imagePath`; picking a pack icon
// sets `imagePath` (with tint for mono SVGs) and clears `symbol`.

struct IconPicker: View {
    @Binding var symbol: String
    @Binding var imagePath: String
    @Binding var tintIcon: Bool

    @EnvironmentObject var packManager: IconPackManager
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selectedTab = "system"

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $selectedTab) {
                Text("System").tag("system")
                ForEach(packManager.packs) { pack in
                    Text(pack.name).tag(pack.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Search icons…", text: $search)
                .textFieldStyle(.roundedBorder)

            if selectedTab == "system" {
                systemGrid
            } else if let pack = packManager.packs.first(where: { $0.id == selectedTab }) {
                packGrid(pack)
            }

            HStack {
                if selectedTab == "system" {
                    Button("Use typed name") {
                        if !search.isEmpty { pickSymbol(search) }
                    }
                    .disabled(search.isEmpty)
                }
                Spacer()
                Button("Clear icon") {
                    symbol = ""
                    imagePath = ""
                    tintIcon = false
                    dismiss()
                }
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .frame(width: 520, height: 460)
    }

    // MARK: System (SF Symbols)

    private var filteredSymbols: [String] {
        search.isEmpty
            ? SymbolPicker.library
            : SymbolPicker.library.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private var systemGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                ForEach(filteredSymbols, id: \.self) { name in
                    Button { pickSymbol(name) } label: {
                        Image(systemName: name)
                            .font(.system(size: 20))
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }
            .padding(4)
        }
    }

    // MARK: Pack grids

    private func packGrid(_ pack: IconPack) -> some View {
        let icons = search.isEmpty
            ? pack.icons
            : pack.icons.filter { $0.name.localizedCaseInsensitiveContains(search) }

        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                ForEach(icons) { icon in
                    Button { pickPackIcon(icon) } label: {
                        Group {
                            if let img = IconThumbnails.image(forPath: icon.path) {
                                Image(nsImage: img)
                                    .renderingMode(img.isTemplate ? .template : .original)
                            } else {
                                Image(systemName: "questionmark.square.dashed")
                            }
                        }
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                    .help(icon.name)
                }
            }
            .padding(4)
        }
    }

    // MARK: selection

    private func pickSymbol(_ name: String) {
        symbol = name
        imagePath = ""
        tintIcon = false
        dismiss()
    }

    private func pickPackIcon(_ icon: IconPack.IconEntry) {
        imagePath = icon.path
        symbol = ""
        // Mono SVG packs (stroke currentColor) need a white tint on dark tiles
        tintIcon = icon.path.lowercased().hasSuffix(".svg")
        dismiss()
    }
}
