import Foundation

// Free space on a mounted volume, via the standard URL resource values API;
// no private frameworks, no entitlements. Mirrors SystemMeter's approach for
// CPU/RAM.
enum DiskSpaceMeter {
    struct Reading {
        let freeBytes: Int64
        let totalBytes: Int64
        var usedFraction: Double {
            guard totalBytes > 0 else { return 0 }
            return 1 - (Double(freeBytes) / Double(totalBytes))
        }
    }

    static func reading(forVolumeAt path: String) -> Reading? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]) else { return nil }
        guard let total = values.volumeTotalCapacity else { return nil }
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        return Reading(freeBytes: free, totalBytes: Int64(total))
    }

    /// Every mounted, user-visible volume; the boot volume ("/") always
    /// comes first labeled "Macintosh HD"-style by its actual display name.
    static func mountedVolumes() -> [(name: String, path: String)] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        var result: [(name: String, path: String)] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable != false,
                  let name = values.volumeName
            else { continue }
            result.append((name, url.path))
        }
        if !result.contains(where: { $0.path == "/" }) {
            result.insert(("Macintosh HD", "/"), at: 0)
        }
        return result
    }

    /// e.g. "512 GB free"; binary (1024-based) units to match Finder/Disk
    /// Utility rather than marketing decimal GB.
    static func formattedFree(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary) + " free"
    }
}
