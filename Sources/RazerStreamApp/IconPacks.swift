import Foundation
import AppKit

// Icon packs are folders of SVG or PNG files; a pack is anything we can scan.
// Two sources: packs bundled in the app's Resources/IconPacks directory, and
// user folders added in Settings (any folder of images, including Stream Deck
// icon packs).

// MARK: - Stable paths for bundled pack icons

/// Bundled pack icons must not be stored as absolute paths into the running
/// .app. Gatekeeper App Translocation (and simply moving/updating the app)
/// changes that path every launch, so profiles that saved
/// `/var/.../AppTranslocation/.../IconPacks/Bootstrap/foo.svg` lose every
/// pack icon on reload even though the profile JSON still has the strings.
///
/// Storage form for bundled icons: `IconPacks/<PackName>/<file>`
/// (relative to `Bundle.main.resourceURL`). User-picked files outside the
/// app keep their absolute paths.
enum IconPath {
    /// Form written into profiles and Recent. Bundled pack files become a
    /// stable relative path; everything else is left alone.
    static func stabilize(_ path: String) -> String {
        if path.hasPrefix("IconPacks/") { return path }

        // Any .app bundle's Resources/IconPacks (installed, translocation,
        // Xcode build products under *.app/Contents/Resources/...).
        let marker = "/Contents/Resources/IconPacks/"
        if let range = path.range(of: marker) {
            return "IconPacks/" + path[range.upperBound...]
        }

        // SPM / non-bundled debug layouts: Resources is the resource root.
        if let resourceURL = Bundle.main.resourceURL {
            let iconRoot = resourceURL.appendingPathComponent("IconPacks", isDirectory: true)
                .standardizedFileURL.path
            let standardized = (path as NSString).standardizingPath
            if standardized.hasPrefix(iconRoot + "/") {
                return "IconPacks/" + standardized.dropFirst(iconRoot.count + 1)
            }
        }
        return path
    }

    /// Absolute path suitable for `NSImage(contentsOfFile:)`. Returns nil when
    /// a relative pack path cannot be found in the current bundle. Absolute
    /// paths that no longer exist are re-homed when they look like old pack
    /// paths into a previous .app location.
    static func resolved(_ path: String) -> String? {
        if path.hasPrefix("IconPacks/") {
            return resolvedBundled(path)
        }

        if FileManager.default.fileExists(atPath: path) {
            return path
        }

        let stable = stabilize(path)
        if stable != path, stable.hasPrefix("IconPacks/") {
            return resolvedBundled(stable)
        }
        return nil
    }

    /// Prefer resolved; fall back to the stored string so callers that only
    /// need a display name still work when the file is missing.
    static func resolvedOrStored(_ path: String) -> String {
        resolved(path) ?? path
    }

    private static func resolvedBundled(_ relative: String) -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let full = resourceURL.appendingPathComponent(relative).path
        return FileManager.default.fileExists(atPath: full) ? full : nil
    }
}

struct IconPack: Identifiable, Equatable {
    let id: String            // stable key; directory path
    let name: String
    let directory: URL
    let icons: [IconEntry]    // sorted by name

    struct IconEntry: Identifiable, Equatable {
        var id: String { path }
        let name: String      // filename without extension, for search
        /// Stored form: relative `IconPacks/...` for bundled packs, absolute
        /// for user folders.
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

        // Bundled packs live in Resources/IconPacks/<PackName>/; store paths
        // relative to the resource root so profiles survive app moves.
        if let resourceURL = Bundle.main.resourceURL {
            let bundledRoot = resourceURL.appendingPathComponent("IconPacks", isDirectory: true)
            found.append(contentsOf: Self.scanRoot(bundledRoot, relativeTo: resourceURL))
        }

        // Each user folder is one pack named after the folder (absolute paths)
        for path in userFolders {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if let pack = Self.scanPack(at: url, relativeTo: nil) {
                found.append(pack)
            }
        }

        packs = found
    }

    // MARK: scanning

    private static func scanRoot(_ root: URL, relativeTo base: URL) -> [IconPack] {
        guard let subdirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return subdirs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { scanPack(at: $0, relativeTo: base) }
            .sorted { $0.name < $1.name }
    }

    private static func scanPack(at dir: URL, relativeTo base: URL?) -> IconPack? {
        let exts = Set(["svg", "png", "jpg", "jpeg", "tiff", "heic"])
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        let basePath = base.map { $0.standardizedFileURL.path }

        let icons = files
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .map { file -> IconPack.IconEntry in
                let name = file.deletingPathExtension().lastPathComponent
                let path: String
                if let basePath {
                    let filePath = file.standardizedFileURL.path
                    if filePath.hasPrefix(basePath + "/") {
                        path = String(filePath.dropFirst(basePath.count + 1))
                    } else {
                        path = IconPath.stabilize(filePath)
                    }
                } else {
                    path = file.path
                }
                return IconPack.IconEntry(name: name, path: path)
            }
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
        let filePath = IconPath.resolvedOrStored(path)
        let key = "\(filePath)#\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let full = NSImage(contentsOfFile: filePath) else { return nil }
        // Rasterize at 2x for retina so small vector icons stay crisp
        let px = side * 2
        let thumb = NSImage(size: NSSize(width: px, height: px), flipped: false) { rect in
            full.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        thumb.size = NSSize(width: side, height: side)
        thumb.isTemplate = filePath.lowercased().hasSuffix(".svg")
        cache.setObject(thumb, forKey: key)
        return thumb
    }
}
