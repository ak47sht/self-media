import Foundation

/// Local persistence for favorites, history, and queue.
/// Uses UserDefaults with JSON encoding — simple, no external dependencies,
/// sufficient for local macOS media app usage.
@MainActor
final class LocalStore: ObservableObject {
    @Published var favorites: [FavoriteItem] = []
    @Published var history: [HistoryItem] = []
    @Published var queue: [QueueItem] = []
    @Published var playlists: [PlaylistGroup] = []

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let favorites = "com.openclaw.media.favorites"
        static let history = "com.openclaw.media.history"
        static let queue = "com.openclaw.media.queue"
        static let playlists = "com.openclaw.media.playlists"
    }

    init() {
        load()
    }

    // MARK: - Load

    private func load() {
        favorites = decode(Keys.favorites) ?? []
        history = decode(Keys.history) ?? []
        queue = (decode(Keys.queue) ?? []).sorted { $0.order < $1.order }
        playlists = decode(Keys.playlists) ?? []
    }

    // MARK: - Favorites

    func addFavorite(id: String, type: MediaItemType, title: String, subtitle: String, thumbnailURL: String?, detailPath: String?) {
        guard !favorites.contains(where: { $0.id == id && $0.type == type }) else { return }
        let item = FavoriteItem(id: id, type: type, title: title, subtitle: subtitle, thumbnailURL: thumbnailURL, detailPath: detailPath, addedAt: Date())
        favorites.append(item)
        saveFavorites()
    }

    func removeFavorite(id: String, type: MediaItemType) {
        favorites.removeAll { $0.id == id && $0.type == type }
        saveFavorites()
    }

    func isFavorite(id: String, type: MediaItemType) -> Bool {
        favorites.contains { $0.id == id && $0.type == type }
    }

    func toggleFavorite(id: String, type: MediaItemType, title: String, subtitle: String, thumbnailURL: String?, detailPath: String?) {
        if isFavorite(id: id, type: type) {
            removeFavorite(id: id, type: type)
        } else {
            addFavorite(id: id, type: type, title: title, subtitle: subtitle, thumbnailURL: thumbnailURL, detailPath: detailPath)
        }
    }

    func favoritesOfType(_ type: MediaItemType) -> [FavoriteItem] {
        favorites.filter { $0.type == type }
    }

    // MARK: - History

    func addToHistory(id: String, type: MediaItemType, title: String, subtitle: String, thumbnailURL: String?, detailPath: String?) {
        if let index = history.firstIndex(where: { $0.id == id && $0.type == type }) {
            history[index].lastPlayedAt = Date()
            history[index].playCount += 1
            // Move to top
            let item = history.remove(at: index)
            history.insert(item, at: 0)
        } else {
            let item = HistoryItem(id: id, type: type, title: title, subtitle: subtitle, thumbnailURL: thumbnailURL, detailPath: detailPath, lastPlayedAt: Date(), playCount: 1)
            history.insert(item, at: 0)
        }
        // Keep last 100 items
        if history.count > 100 { history = Array(history.prefix(100)) }
        saveHistory()
    }

    func recentHistory(limit: Int = 20) -> [HistoryItem] {
        Array(history.prefix(limit))
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    // MARK: - Queue

    func enqueue(id: String, type: MediaItemType, title: String, subtitle: String, thumbnailURL: String?, detailPath: String?, streamURL: String?) {
        let nextOrder = (queue.map(\.order).max() ?? -1) + 1
        let item = QueueItem(id: id, type: type, title: title, subtitle: subtitle, thumbnailURL: thumbnailURL, detailPath: detailPath, streamURL: streamURL, order: nextOrder, addedAt: Date())
        queue.append(item)
        saveQueue()
    }

    func dequeue(_ item: QueueItem) {
        queue.removeAll { $0.id == item.id }
        saveQueue()
    }

    func dequeue(at index: Int) {
        guard index < queue.count else { return }
        queue.remove(at: index)
        saveQueue()
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        // Re-number orders
        for i in queue.indices { queue[i].order = i }
        saveQueue()
    }

    func clearQueue() {
        queue = []
        saveQueue()
    }

    func nextInQueue() -> QueueItem? {
        queue.sorted { $0.order < $1.order }.first
    }

    func isInQueue(id: String, type: MediaItemType) -> Bool {
        queue.contains { $0.id == id && $0.type == type }
    }

    // MARK: - Persistence

    private func saveFavorites() {
        encode(favorites, key: Keys.favorites)
    }

    private func saveHistory() {
        encode(history, key: Keys.history)
    }

    private func saveQueue() {
        encode(queue, key: Keys.queue)
    }

    private func savePlaylists() {
        encode(playlists, key: Keys.playlists)
    }

    private func encode<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func decode<T: Codable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
