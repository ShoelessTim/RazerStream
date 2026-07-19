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
    @State private var selectedTab = RecentIcons.items.isEmpty ? "system" : "recent"

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $selectedTab) {
                Text("Recent").tag("recent")
                Text("System").tag("system")
                ForEach(packManager.packs) { pack in
                    Text(pack.name).tag(pack.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Search icons…", text: $search)
                .textFieldStyle(.roundedBorder)

            if selectedTab == "recent" {
                recentGrid
            } else if selectedTab == "system" {
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

    // MARK: Recent

    private var filteredRecents: [RecentIcon] {
        let all = RecentIcons.items
        guard !search.isEmpty else { return all }
        return all.filter {
            ($0.symbol ?? ($0.imagePath as NSString?)?.lastPathComponent ?? "")
                .localizedCaseInsensitiveContains(search)
        }
    }

    private var recentGrid: some View {
        ScrollView {
            if filteredRecents.isEmpty {
                Text(RecentIcons.items.isEmpty ? "Icons you pick will show up here." : "No matches.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 10) {
                    ForEach(Array(filteredRecents.enumerated()), id: \.offset) { _, recent in
                        Button {
                            if let symbol = recent.symbol {
                                pickSymbol(symbol)
                            } else if let path = recent.imagePath {
                                pickPackIcon(IconPack.IconEntry(name: (path as NSString).lastPathComponent, path: path))
                            }
                        } label: {
                            Group {
                                if let symbol = recent.symbol {
                                    Image(systemName: symbol).font(.system(size: 20))
                                } else if let path = recent.imagePath, let img = IconThumbnails.image(forPath: path) {
                                    Image(nsImage: img)
                                        .renderingMode(recent.tint ? .template : .original)
                                } else {
                                    Image(systemName: "questionmark.square.dashed")
                                }
                            }
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                        }
                        .buttonStyle(.plain)
                        .help(recent.symbol ?? (recent.imagePath.map { ($0 as NSString).lastPathComponent } ?? ""))
                    }
                }
                .padding(4)
            }
        }
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
        RecentIcons.record(symbol: name, imagePath: nil, tint: false)
        dismiss()
    }

    private func pickPackIcon(_ icon: IconPack.IconEntry) {
        // Stabilize so bundled pack paths don't bake in App Translocation or
        // a one-shot .app location (that is what made pack icons vanish on
        // every relaunch in 1.5.0 and earlier).
        let stored = IconPath.stabilize(icon.path)
        imagePath = stored
        symbol = ""
        // Mono SVG packs (stroke currentColor) need a white tint on dark tiles
        tintIcon = stored.lowercased().hasSuffix(".svg")
        RecentIcons.record(symbol: nil, imagePath: stored, tint: tintIcon)
        dismiss()
    }
}
