import Foundation
import AppKit

// Icon packs are folders of SVG or PNG files; a pack is anything we can scan.
// Two sources: packs bundled in the app's Resources/IconPacks directory, and
// user folders added in Settings (any folder of images, including Stream Deck
// icon packs).

struct IconPack: Identifiable, Equatable {
    let id: String            // stable key; directory path
    let name: String
    let directory: URL
    let icons: [IconEntry]    // sorted by name

    struct IconEntry: Identifiable, Equatable {
        var id: String { path }
        let name: String      // filename without extension, for search
        let path: String
    }
}

@MainActor
final class IconPackManager: ObservableObject {
    @Published private(set) var packs: [IconPack] = []

    // User folder paths persist as a JSON array of strings
    private let defaultsKey = "userIconPackFolders"

    init() {
        rescan()
    }

    var userFolders: [String] {
        get { UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    func addUserFolder(_ url: URL) {
        var folders = userFolders
        guard !folders.contains(url.path) else { return }
        folders.append(url.path)
        userFolders = folders
        rescan()
    }

    func removeUserFolder(_ path: String) {
        userFolders = userFolders.filter { $0 != path }
        rescan()
    }

    func rescan() {
        var found: [IconPack] = []

        // Bundled packs live in Resources/IconPacks/<PackName>/
        if let resourceURL = Bundle.main.resourceURL {
            let bundledRoot = resourceURL.appendingPathComponent("IconPacks", isDirectory: true)
            found.append(contentsOf: Self.scanRoot(bundledRoot))
        }

        // Each user folder is one pack named after the folder
        for path in userFolders {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if let pack = Self.scanPack(at: url) {
                found.append(pack)
            }
        }

        packs = found
    }

    // MARK: scanning

    private static func scanRoot(_ root: URL) -> [IconPack] {
        guard let subdirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return subdirs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { scanPack(at: $0) }
            .sorted { $0.name < $1.name }
    }

    private static func scanPack(at dir: URL) -> IconPack? {
        let exts = Set(["svg", "png", "jpg", "jpeg", "tiff", "heic"])
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        let icons = files
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .map { IconPack.IconEntry(name: $0.deletingPathExtension().lastPathComponent, path: $0.path) }
            .sorted { $0.name < $1.name }

        guard !icons.isEmpty else { return nil }
        return IconPack(id: dir.path, name: dir.lastPathComponent, directory: dir, icons: icons)
    }
}

// Small thumbnail cache so scrolling a 1500 icon grid stays smooth;
// main actor because all callers are SwiftUI views
@MainActor
enum IconThumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(forPath path: String, side: CGFloat = 28) -> NSImage? {
        let key = "\(path)#\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let full = NSImage(contentsOfFile: path) else { return nil }
        // Rasterize at 2x for retina so small vector icons stay crisp
        let px = side * 2
        let thumb = NSImage(size: NSSize(width: px, height: px), flipped: false) { rect in
            full.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        thumb.size = NSSize(width: side, height: side)
        thumb.isTemplate = path.lowercased().hasSuffix(".svg")
        cache.setObject(thumb, forKey: key)
        return thumb
    }
}
