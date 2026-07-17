import Foundation

// Backs the icon library's Recent tab. Stored in UserDefaults (small, not
// profile content) as a capped, most-recent-first list; each entry mirrors
// the same symbol/imagePath/tint trio TileConfig and KnobConfig use, so a
// recent entry can be applied back exactly as it was picked.
struct RecentIcon: Codable, Equatable {
    var symbol: String?
    var imagePath: String?
    var tint: Bool
}

enum RecentIcons {
    private static let key = "recentIconsData"
    private static let limit = 24

    static var items: [RecentIcon] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([RecentIcon].self, from: data)
            else { return [] }
            return decoded
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    /// Moves this icon to the front, dropping any older entry for the same
    /// icon, and calls it after every pick in IconPicker.
    static func record(symbol: String?, imagePath: String?, tint: Bool) {
        guard (symbol?.isEmpty == false) || (imagePath?.isEmpty == false) else { return }
        var list = items
        list.removeAll { $0.symbol == symbol && $0.imagePath == imagePath }
        list.insert(RecentIcon(symbol: symbol, imagePath: imagePath, tint: tint), at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        items = list
    }
}
